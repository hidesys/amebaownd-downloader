require 'rubygems'
require 'bundler'
require 'digest/md5'
require 'json'
require 'yaml'
require 'sanitize'
Bundler.require

SLEEP_SECOND = 3
XPATHES = {
  datetime: "//time[contains(@class,'blog-article__date')]",
  title: "//h1[contains(@class,'blog-title__text')]",
  content: "//div[contains(@class,'blog-article__body')]"
}
IMAGE_MATCH = /^https\:\\u002F\\u002Fcdn.amebaowndme.com[\:\w\-\\\.]+jpg/
IMAGE_COUNT_XPATH = "//div[contains(@class,'blog-article__body')]//div[contains(@class,'img')]"

site = ARGV[0]
directory = ARGV[1] || ['sites', site].join('/')

if site.nil? || site.empty?
  puts
  puts "Usage: #{File.basename(__FILE__)} URL [directory to save in]"
  puts "eg. #{File.basename(__FILE__)} blog.cottonakameguro.com"
  puts "eg. #{File.basename(__FILE__)} blog.cottonakameguro.com ~/documents/downloaded_site/"
  puts
  exit 1
end

def create_agent()
  agent = Mechanize.new
  agent.user_agent_alias = 'Windows Mozilla'
  agent.max_history = 1
  agent
end

def fetch_or_read(agent:, url:, filepath:)
  content = nil
  if File.exists?(filepath)
    content = File.open(filepath, 'r').read
  else
    sleep SLEEP_SECOND
    puts "Downloading... : #{url}"
    begin
      page = agent.get(url)
      content = page.body.to_s
      File.open(filepath, 'w').write(content)
    rescue => ex
      puts ex
    end
  end
  content
end

def sanitize(html)
  elements = %w(a h1 h2 h3 b font span u)
  text = Sanitize.fragment(
    html,
    elements: elements,
    attributes: {
      'a' => ['href', 'target', 'style'],
      'font' => ['style'],
      'span' => ['style'],
      'h1' => ['style'],
      'h2' => ['style'],
      'h3' => ['style'],
      'u' => ['style']
    }
  ).gsub('&nbsp;', '').gsub(
    /[\s\t]*\n+[\s\t]*\n+[\s\t\n]*/,
    "\n\n"
  ).strip
  paraed = text.split("\n\n").map{ |para| "<p>#{para}</p>" }.join("\n").gsub(
    /[\s\t]*\n[\s\t\n]*/, "\n"
  )
  doc = Nokogiri::HTML.parse(paraed)
  (elements + ['p']).each do |name|
    doc.search("//#{name}").each do |element|
      element.remove if !element.inner_html || element.inner_html =~ /^[\s\t\n]*$/
    end
  end
  doc.at('body').inner_html.strip
end

# Create directories
logs = [directory, 'logs'].join('/')
FileUtils.mkdir_p(logs)

puts "Downloading articles from #{site.inspect} ..."

agent = create_agent
sitemap = fetch_or_read(
  agent: agent,
  url: "https://#{site}/sitemap.xml",
  filepath: [logs, 'sitemap.xml'].join('/')
)
article_urls = Nokogiri::XML.parse(sitemap).xpath('//text()').map(&:to_s).select { |text| text =~ /^http.+\/posts\/\d+/ }
article_urls.each do |url|
  filepath = "#{directory}/#{url.split('/').last}.html"
  body = fetch_or_read(agent: agent, url: url, filepath: filepath)
  doc = Nokogiri::HTML(body)
  data = {}
  XPATHES.each do |key, xpath|
    data[key] = sanitize(doc.xpath(xpath).inner_html)
  end
  image_urls = body.split("\"").select { |item| item =~ IMAGE_MATCH }.map { |url| JSON.parse("\"#{url}\"") }.uniq
  image_count = doc.xpath(IMAGE_COUNT_XPATH).length
  image_count -= 1 if body =~ /blogmura/
  image_urls[0...image_count].each_with_index do |image_url, i|
    image_path = "#{directory}/#{url.split('/').last}_#{i}_#{image_url.split('/').last}"
    fetch_or_read(agent: agent, url: image_url, filepath: image_path)
  end
  yml_path = "#{directory}/#{url.split('/').last}.yml"
  File.open(yml_path, 'w').write data.to_yaml
end
