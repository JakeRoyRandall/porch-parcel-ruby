require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'stringio'
require_relative '../app/packer'

class PorchParcelTest < Minitest::Test
  def test_first_fit_geometry_is_row_major
    result = PorchParcel.pack('shelf_width' => 5, 'shelf_height' => 3, 'parcels' => [
      {'id' => 'A', 'width' => 2, 'height' => 2}, {'id' => 'B', 'width' => 3, 'height' => 1}
    ])
    assert_equal [['A', 'A', 'B', 'B', 'B'], ['A', 'A', nil, nil, nil], [nil, nil, nil, nil, nil]], result[:grid]
    assert_equal [['A', 0, 0], ['B', 2, 0]], result[:placed].map { |p| [p.parcel.id, p.x, p.y] }
    assert_equal 'first-fit', result[:strategy]
  end
  def test_area_strategy_is_stable_and_identified
    data = {'shelf_width' => 5, 'shelf_height' => 3, 'parcels' => [{'id' => 'small', 'width' => 1, 'height' => 1}, {'id' => 'large', 'width' => 3, 'height' => 2}, {'id' => 'medium', 'width' => 2, 'height' => 1}]}
    first = PorchParcel.pack(data)
    area = PorchParcel.pack(data, strategy: 'area')
    assert_equal ['small', 'large', 'medium'], first[:placed].map { |p| p.parcel.id }
    assert_equal ['large', 'medium', 'small'], area[:placed].map { |p| p.parcel.id }
    assert_includes PorchParcel.html(area), 'Strategy: area'
    assert_raises(ArgumentError) { PorchParcel.pack(data, strategy: 'sideways') }
  end
  def test_best_fit_is_distinct_deterministic_heuristic
    data = {'shelf_width' => 5, 'shelf_height' => 4, 'parcels' => [
      {'id' => 'a', 'width' => 1, 'height' => 1}, {'id' => 'b', 'width' => 1, 'height' => 2},
      {'id' => 'c', 'width' => 4, 'height' => 3}, {'id' => 'd', 'width' => 1, 'height' => 3}
    ]}
    first = PorchParcel.pack(data)
    best = PorchParcel.pack(data, strategy: 'best-fit')
    assert_equal ['a', 'b', 'd'], first[:placed].map { |p| p.parcel.id }
    assert_equal ['a', 'b', 'c'], best[:placed].map { |p| p.parcel.id }
    assert_operator best[:placed].sum { |p| p.width * p.height }, :>, first[:placed].sum { |p| p.width * p.height }
    assert_equal best[:grid], PorchParcel.pack(data, strategy: 'best-fit')[:grid]
  end
  def test_best_fit_considers_later_positions_and_respects_clearance
    data = {'shelf_width' => 4, 'shelf_height' => 2, 'blocked' => [{'x' => 0, 'y' => 0}], 'parcels' => [{'id' => 'a', 'width' => 1, 'height' => 1}, {'id' => 'b', 'width' => 1, 'height' => 1}]}
    result = PorchParcel.pack(data, strategy: 'best-fit')
    assert_equal [3, 1], [result[:placed][0].x, result[:placed][0].y]
    assert_equal [3, 0], [result[:placed][1].x, result[:placed][1].y]
    occupied = result[:grid].flatten.compact
    assert_equal occupied.length, occupied.count { |id| %w[a b].include?(id) }
    assert_equal [[0, 0]], result[:blocked]
  end
  def test_area_strategy_can_place_more_area_than_input_order
    data = {'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => [
      {'id' => 'A', 'width' => 1, 'height' => 1}, {'id' => 'B', 'width' => 1, 'height' => 1},
      {'id' => 'C', 'width' => 1, 'height' => 1}, {'id' => 'D', 'width' => 1, 'height' => 2}
    ]}
    first = PorchParcel.pack(data); area = PorchParcel.pack(data, strategy: 'area')
    assert_equal 3, first[:placed].length; assert_equal 3, area[:placed].length
    assert_operator area[:placed].sum { |p| p.width * p.height }, :>, first[:placed].sum { |p| p.width * p.height }
  end
  def test_exact_edge_fit
    result = PorchParcel.pack('shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => 'edge', 'width' => 4, 'height' => 2}])
    assert_empty result[:unplaced]; assert_equal [0, 0], [result[:placed][0].x, result[:placed][0].y]
  end
  def test_rotation_places_parcel_that_only_fits_turning
    data = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}
    assert_equal ['turn'], PorchParcel.pack(data)[:unplaced]
    result = PorchParcel.pack(data, rotate: true)
    refute_empty result[:placed]; assert result[:placed][0].rotated; assert_equal [3, 2], [result[:placed][0].width, result[:placed][0].height]
  end
  def test_original_orientation_wins_tie
    result = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 3, 'parcels' => [{'id' => 'tie', 'width' => 2, 'height' => 2}]}, rotate: true)
    refute result[:placed][0].rotated
  end
  def test_rotation_has_no_overlaps
    result = PorchParcel.pack({'shelf_width' => 4, 'shelf_height' => 4, 'parcels' => [
      {'id' => 'A', 'width' => 3, 'height' => 2}, {'id' => 'B', 'width' => 2, 'height' => 3}
    ]}, rotate: true)
    occupied = result[:grid].flatten.compact; assert_equal occupied.uniq.sort, %w[A B].sort
  end
  def test_unplaced_when_no_rectangle_remains
    result = PorchParcel.pack('shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'A', 'width' => 2, 'height' => 2}, {'id' => 'B', 'width' => 2, 'height' => 1}])
    assert_equal ['B'], result[:unplaced]
  end
  def test_blocked_cells_reduce_capacity_and_are_reported_in_html
    data = {'shelf_width' => 2, 'shelf_height' => 2, 'blocked' => [{'x' => 1, 'y' => 0}], 'parcels' => [{'id' => 'A', 'width' => 2, 'height' => 2}]}
    result = PorchParcel.pack(data)
    assert_equal [[1, 0]], result[:blocked]
    assert_equal ['A'], result[:unplaced]
    page = PorchParcel.html(result)
    assert_includes page, 'usable area'
    assert_includes page, 'Usable area: 3'
    assert_includes page, 'Blocked shelf cell at 1,0'
    assert_includes page, 'repeating-linear-gradient'
    assert_includes page, 'position:absolute'
    output = StringIO.new
    PorchParcel.render(result, output)
    assert_includes output.string, 'Blocked: 1 cell(s); usable area: 3'
  end
  def test_unblocked_cli_render_keeps_original_summary_shape
    data = {'shelf_width' => 1, 'shelf_height' => 1, 'parcels' => []}
    result = PorchParcel.pack(data)
    output = StringIO.new; PorchParcel.render(result, output)
    explicit = StringIO.new; PorchParcel.render(PorchParcel.pack(data, margin: 0), explicit)
    assert_equal output.string, explicit.string
    assert_equal 'PORCH PARCEL // 1x1 shelf // first-fit', output.string.lines.first.chomp
    refute_includes output.string, 'Blocked:'
  end
  def test_cli_explicit_zero_margin_matches_default_text
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json')
      File.write(input, JSON.generate('shelf_width' => 2, 'shelf_height' => 2, 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      default = `ruby #{script} #{input}`
      explicit = `ruby #{script} --margin 0 #{input}`
      assert_equal default, explicit
    end
  end
  def test_json_render_is_deterministic_and_contains_placement_geometry
    result = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}, rotate: true)
    output = StringIO.new
    PorchParcel.render_json(result, output)
    payload = JSON.parse(output.string)
    assert_equal %w[shelf_width shelf_height strategy margin blocked placed unplaced occupied_area usable_area], payload.keys
    assert_equal [], payload['blocked']
    assert_equal ['turn'], payload['placed'].map { |p| p['id'] }
    assert_equal true, payload['placed'][0]['rotated']
    assert_equal 6, payload['occupied_area']
    assert_equal 6, payload['usable_area']
  end
  def test_cli_json_stdout_is_parseable_and_errors_stay_on_stderr
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json')
      File.write(input, JSON.generate('shelf_width' => 2, 'shelf_height' => 2, 'blocked' => [{'x' => 1, 'y' => 0}], 'parcels' => [{'id' => 'box', 'width' => 1, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      stdout = `ruby #{script} --json #{input}`
      payload = JSON.parse(stdout)
      assert_equal 2, payload['shelf_width']
      assert_equal 'box', payload['placed'][0]['id']
      error = `ruby #{script} --json #{dir}/missing.json 2>&1`
      assert_includes error, 'Input error'
      refute_includes error, '{"shelf_width"'
    end
  end
  def test_margin_requires_clear_shelf_boundary_and_separates_parcels
    tight = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 1, 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}]}, margin: 1)
    assert_equal ['A'], tight[:unplaced]
    separated = PorchParcel.pack({'shelf_width' => 5, 'shelf_height' => 3, 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}, {'id' => 'B', 'width' => 1, 'height' => 1}]}, margin: 1)
    assert_equal [[1, 1], [3, 1]], separated[:placed].map { |p| [p.x, p.y] }
    assert_equal 1, separated[:margin]
  end
  def test_margin_supports_rotated_parcel_and_blocked_obstacle
    rotated = PorchParcel.pack({'shelf_width' => 4, 'shelf_height' => 5, 'parcels' => [{'id' => 'turn', 'width' => 3, 'height' => 2}]}, rotate: true, margin: 1)
    assert_equal ['turn'], rotated[:placed].map { |p| p.parcel.id }
    assert rotated[:placed][0].rotated
    blocked = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 3, 'blocked' => [{'x' => 1, 'y' => 1}], 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}]}, margin: 1)
    assert_equal ['A'], blocked[:unplaced]
  end
  def test_margin_is_reported_in_all_output_formats_and_validated
    result = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 3, 'parcels' => []}, margin: 2)
    text = StringIO.new; PorchParcel.render(result, text)
    assert_includes text.string, 'margin 2'
    json = StringIO.new; PorchParcel.render_json(result, json)
    assert_equal 2, JSON.parse(json.string)['margin']
    assert_includes PorchParcel.html(result), 'Margin: 2'
    assert_raises(ArgumentError) { PorchParcel.pack({'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => []}, margin: 4) }
    assert_raises(ArgumentError) { PorchParcel.pack({'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => []}, margin: 1.0) }
  end
  def test_rotation_can_fit_around_blocked_cell
    data = {'shelf_width' => 3, 'shelf_height' => 3, 'blocked' => [{'x' => 0, 'y' => 0}, {'x' => 1, 'y' => 0}], 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}
    result = PorchParcel.pack(data, rotate: true)
    assert_equal ['turn'], result[:placed].map { |p| p.parcel.id }
    assert result[:placed][0].rotated
    refute_equal [0, 0], [result[:placed][0].x, result[:placed][0].y]
  end
  def test_blocked_schema_rejects_duplicates_and_out_of_bounds
    base = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => []}
    assert_raises(ArgumentError) { PorchParcel.pack(base.merge('blocked' => [{'x' => 1, 'y' => 1}, {'x' => 1, 'y' => 1}])) }
    assert_raises(ArgumentError) { PorchParcel.pack(base.merge('blocked' => [{'x' => 3, 'y' => 0}])) }
    assert_raises(ArgumentError) { PorchParcel.pack(base.merge('blocked' => [{'x' => 1.0, 'y' => 0}])) }
  end
  def test_malformed_schema_is_rejected
    bad = {'shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => 'x', 'width' => 1, 'height' => 1}, {'id' => 'x', 'width' => 1, 'height' => 1}]}
    assert_raises(ArgumentError) { PorchParcel.pack(bad) }
    assert_raises(ArgumentError) { PorchParcel.pack('shelf_width' => 4.0, 'shelf_height' => 2, 'parcels' => []) }
    assert_raises(ArgumentError) { PorchParcel.pack('shelf_width' => 41, 'shelf_height' => 2, 'parcels' => []) }
    assert_raises(ArgumentError) { PorchParcel.pack('shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => "bad\nline", 'width' => 1, 'height' => 1}]) }
  end
  def test_cli_rejects_bad_paths_args_and_oversize_without_traceback
    Dir.mktmpdir do |dir|
      script = File.expand_path('../app/packer.rb', __dir__)
      missing = `ruby #{script} #{dir}/missing.json 2>&1`; assert_includes missing, 'Input error'; refute_includes missing, 'Traceback'
      directory = `ruby #{script} #{dir} 2>&1`; assert_includes directory, 'Input error'; refute_includes directory, 'Traceback'
      too_big = File.join(dir, 'big.json'); File.write(too_big, 'x' * (1024 * 1024 + 1))
      oversized = `ruby #{script} #{too_big} 2>&1`; assert_includes oversized, 'Input error'; refute_includes oversized, 'Traceback'
      extra = `ruby #{script} one.json two.json 2>&1`; assert_includes extra, 'exactly one input path'; refute_includes extra, 'Traceback'
      unknown = `ruby #{script} --wat one.json 2>&1`; assert_includes unknown, 'unknown flag'; refute_includes unknown, 'Traceback'
    end
  end
  def test_html_report_contains_geometry_labels_and_area
    result = PorchParcel.pack('shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => 'box1', 'width' => 2, 'height' => 1}, {'id' => 'box2', 'width' => 1, 'height' => 2}])
    page = PorchParcel.html(result)
    assert_includes page, '<!doctype html>'; assert_includes page, 'box1'; assert_includes page, '2×1'; assert_includes page, 'occupied area'; assert_includes page, 'width:50.0%'; assert_includes page, 'height:100.0%'
    square = PorchParcel.html(PorchParcel.pack('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => []))
    assert_includes square, 'aspect-ratio:1/1'; assert_includes square, 'background-size:calc(100% / 1) calc(100% / 1)'
  end
  def test_cli_html_export_and_existing_file_guard
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json'); output = File.join(dir, 'report.html')
      File.write(input, JSON.generate('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => [{'id' => 'x', 'width' => 1, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      first = `ruby #{script} --html #{output} #{input}`; assert File.file?(output); assert_includes File.read(output), 'x'
      second = `ruby #{script} --html #{output} #{input} 2>&1`; assert_includes second, 'output exists'
      forced = `ruby #{script} --html #{output} --force #{input}`; assert File.file?(output); refute_includes forced, 'Traceback'
    end
  end
end
