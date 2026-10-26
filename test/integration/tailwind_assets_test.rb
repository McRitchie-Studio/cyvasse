require "test_helper"

# [integration] The pages link the Tailwind build that application.css makes
# through studio-engine's host.css (task satellites-adopt-css-first-tailwind),
# and every /assets URL a page names is served. The build carries one class
# from each thing host.css brings (studio-engine README, "Tailwind", step 5):
# .text-heading (the theme tokens), .btn-primary (the component layer, found by
# the engine scan) and .spinner (the motion layer).
class TailwindAssetsTest < ActionDispatch::IntegrationTest
  test "the home page names only assets that are served" do
    get root_path
    assert_response :success
    assert_every_asset_served
  end

  test "a signed-in page names only assets that are served" do
    log_in_as(User.create!(email: "tailwind@example.com", name: "Tailwind Probe", username: "tailwind_probe"))
    get matches_path
    assert_response :success
    assert_every_asset_served
  end

  test "the linked Tailwind build carries the engine's tokens, components and motion" do
    get root_path
    href = asset_urls.find { |url| url.match?(%r{\A/assets/tailwind-[0-9a-f]+\.css\z}) }
    assert href, "the layout must link the Tailwind build"

    get href
    assert_response :success
    %w[.text-heading{ .btn-primary{ .spinner{].each do |rule|
      assert_includes response.body.delete(" \n"), rule, "the Tailwind build lost #{rule.delete("{")}"
    end
  end

  private

  def asset_urls
    Nokogiri::HTML(response.body).css("link[href], script[src], img[src], source[src]")
            .map { |node| node["href"] || node["src"] }
            .select { |url| url.start_with?("/assets/") }
            .uniq
  end

  def assert_every_asset_served
    urls = asset_urls
    assert urls.any? { |url| url.start_with?("/assets/tailwind-") }, "the page must link the Tailwind build"
    urls.each do |url|
      get url
      assert_response :success, "#{url} is named by the page but not served"
    end
  end
end
