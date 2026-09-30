# Reading the SEO head of a rendered page (task cyvasse-seo-profile).
module SeoAssertions
  def page_doc = Nokogiri::HTML5(response.body)

  def meta_content(doc, selector)
    node = doc.at_css(selector)
    node && (node["content"] || node["href"])
  end

  # Every JSON-LD block on the page, parsed; a block that is not valid JSON
  # raises JSON::ParserError and fails the test.
  def json_ld_blocks(doc = page_doc)
    doc.css('script[type="application/ld+json"]').map { |script| JSON.parse(script.text) }
  end
end
