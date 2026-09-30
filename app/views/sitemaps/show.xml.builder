xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  @pages.each do |page|
    xml.url do
      xml.loc seo_canonical_url(page)
      xml.lastmod SeoPage.lastmod(page).iso8601
      xml.changefreq page.changefreq
      xml.priority page.priority
    end
  end
end
