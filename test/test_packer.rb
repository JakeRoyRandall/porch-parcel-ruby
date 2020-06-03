require 'minitest/autorun'
require 'json'
require 'tmpdir'
require_relative '../app/packer'

class PorchParcelTest < Minitest::Test
  def test_first_fit_geometry_is_row_major
    result = PorchParcel.pack('shelf_width' => 5, 'shelf_height' => 3, 'parcels' => [
      {'id' => 'A', 'width' => 2, 'height' => 2}, {'id' => 'B', 'width' => 3, 'height' => 1}
    ])
    assert_equal [['A', 'A', 'B', 'B', 'B'], ['A', 'A', nil, nil, nil], [nil, nil, nil, nil, nil]], result[:grid]
    assert_equal [['A', 0, 0], ['B', 2, 0]], result[:placed].map { |p| [p.parcel.id, p.x, p.y] }
  end
  def test_exact_edge_fit
    result = PorchParcel.pack('shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => 'edge', 'width' => 4, 'height' => 2}])
    assert_empty result[:unplaced]; assert_equal [0, 0], [result[:placed][0].x, result[:placed][0].y]
  end
  def test_unplaced_when_no_rectangle_remains
    result = PorchParcel.pack('shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'A', 'width' => 2, 'height' => 2}, {'id' => 'B', 'width' => 2, 'height' => 1}])
    assert_equal ['B'], result[:unplaced]
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
    end
  end
end
