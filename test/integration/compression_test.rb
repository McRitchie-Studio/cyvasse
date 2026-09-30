require "test_helper"

# [unit] Rack::Deflater (config/application.rb): text responses go out gzip'd
# to a client that accepts it, raw to one that does not, and images pass
# through untouched. The assets ride the same middleware as the pages.
class CompressionTest < ActionDispatch::IntegrationTest
  GZIP = { "Accept-Encoding" => "gzip, deflate, br" }.freeze

  def gunzip(body)
    Zlib::GzipReader.new(StringIO.new(body)).read
  end

  def asset(logical)
    ActionController::Base.helpers.asset_path(logical)
  end

  test "a page is gzip'd for a client that accepts it" do
    get root_path, headers: GZIP

    assert_response :success
    assert_equal "gzip", response.headers["content-encoding"]
    assert_includes response.headers["vary"].to_s, "Accept-Encoding"
    assert_includes gunzip(response.body), '<html lang="en">'
  end

  test "a page is sent raw to a client that does not ask for gzip" do
    get root_path

    assert_response :success
    assert_nil response.headers["content-encoding"]
    assert_includes response.body, '<html lang="en">'
  end

  test "JSON is gzip'd" do
    post live_seeks_path
    get live_seek_path(LiveSeek.last, format: :json), headers: GZIP

    assert_response :success
    assert_equal "gzip", response.headers["content-encoding"]
    assert JSON.parse(gunzip(response.body)).key?("status")
  end

  test "a JavaScript module and the stylesheet are gzip'd" do
    [ asset("controllers/cyvasse_game_controller.js"), asset("application.js"), asset("tailwind.css") ].each do |path|
      get path, headers: GZIP

      assert_response :success
      assert_equal "gzip", response.headers["content-encoding"], path
      assert_operator gunzip(response.body).bytesize, :>, response.body.bytesize, path
    end
  end

  test "images pass through uncompressed, from the pipeline and from public/" do
    [ asset("bots/aegon.webp"), "/favicon.png" ].each do |path|
      get path, headers: GZIP

      assert_response :success
      assert_nil response.headers["content-encoding"], path
    end
  end
end
