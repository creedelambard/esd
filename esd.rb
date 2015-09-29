#!/usr/bin/ruby

require 'optparse'
require 'mechanize'
require 'awesome_print'
require 'pp'
require 'logger'
require 'mail'
require 'redis'

sbjct = "Amazon and non-Amazon"
options = {}
matchLimit = 100
company_matcher = %r(Amazon)i
base = "https://fortress.wa.gov/esd/worksource"
epoch_current_time = Time.now
redis = Redis.new( server: 'www.lambard.net', db: 6)

Mail.defaults do
  delivery_method :smtp, address: "mail.lambard.net", port: 25, openssl_verify_mode: 'none'
end

already_seen = redis.keys('*')

locations = {
  2500 => "Aberdeen (Grays Harbor Co.)",
  4900 => "Bellingham (Whatcom Co.)",
  2800 => "Bremerton (Kitsap Co.)",
  3200 => "Centralia (Lewis Co.)",
  1200 => "Clarkston (Asotin Co.)",
  1600 => "Columbia County",
  4500 => "Colville (Stevens Co.)",
  1800 => "Douglas County",
  2900 => "Ellensburg (Kittitas Co.)",
  4300 => "Everett (Snohomish Co.)",
  2300 => "Garfield County",
  1700 => "Kelso (Cowlitz Co.)",
  2100 => "King County - Anywhere",
  2110 => "King County - East",
  2120 => "King County - North",
  2130 => "King County - South",
  3100 => "Klickitat County",
  3300 => "Lincoln County",
  2400 => "Moses Lake (Grant Co.)",
  4100 => "Mt. Vernon (Skagit Co.)",
  2600 => "Oak Harbor (Island Co.)",
  4600 => "Olympia (Thurston Co.)",
  3500 => "Omak (Okanogan Co.)",
  2200 => "Pasco (Franklin Co.)",
  3700 => "Pend Oreille County",
  1400 => "Port Angeles (Clallam Co.)",
  2700 => "Port Townsend (Jefferson Co.)",
  5100 => "Pullman (Whitman Co.)",
  3600 => "Raymond (Pacific Co.)",
  1900 => "Republic - Ferry Co.",
  5300 => "Richland/Kennewick (Benton Co.)",
  1100 => "Ritzville (Adams Co.)",
  3900 => "San Juan County",
  2140 => "Seattle (City Of)",
  3400 => "Shelton (Mason Co.)",
  4400 => "Spokane County",
  4200 => "Stevenson (Skamania Co.)",
  3800 => "Tacoma (Pierce Co.)",
  1500 => "Vancouver (Clark Co.)",
  4700 => "Wahkiakum County",
  4800 => "Walla Walla County",
  1300 => "Wenatchee (Chelan Co.)",
  5200 => "Yakima County",
  1000 => "All Counties - Anywhere in WA State",
  10000 => "Other Locations - Outside WA State",
  0 => "All Locations - In State and Out of State" 
  }

options = OpenStruct.new
options.keywordType = 'rdoAll'
options.locations = [ ]
options.searchItems = 500
options.notAmazon = false
options.onlyAmazon = false
options.testing = false
options.alreadySeen = false
options.keywords = [ ]
options.age = 1

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: ruby esd.rb [options]"

  opts.on("--keywordType [TYPE]", ["rdoAll", "rdoAny", "rdoPhrase"],
          "Keyword type (rdoAll, rdoAny or rdoPhrase)") do |t|
    options.keywordType = t
  end

  opts.on("-d", "--age [DAYS]", 
          "Maximum age in days") do |d|
    options.age = d
  end

  opts.on("--dupe", 
          "Show items that have already been processed") do
    options.alreadySeen = true
  end

  opts.on("-l", "--locations x,y,z", Array, 
          "Locations to search (hint: 2100 is 'all of King County')",
          "Can specify more than once (e.g. '-l 2100 -l 4300')") do |t|
    options.locations << t
  end

  opts.on("-k", "--keywords x,y,z", Array, 
          "Keywords to search for (e.g. 'ruby' or 'devops,ruby,rails')",
          "Can specify more than once (e.g. '-k ruby -k rails')") do |k|
    options.keywords << k
  end

  opts.on("-s n", "--searchItems=n", OptionParser::DecimalInteger, "Number of items to search for (default 500)") do |s|
    options.searchItems = s
  end

  opts.on( '-n', '--noAmazon', "Show only non-Amazon results" ) do
    options.notAmazon = true
    sbjct = "non-Amazon"
  end

  opts.on( '-a', '--onlyAmazon', "Show only Amazon results" ) do
    options.onlyAmazon = true
    sbjct = "Amazon only"
  end

  opts.on( '-t', '--test', "Just do a dry run, don't send mail" ) do
    options.testing = true
    $stderr.puts "Testing for #{sbjct} results (limit of #{matchLimit})"
    $stderr.flush
  end

  opts.on( '-h', '--help', "Show this help message" ) do
    puts opts
    exit
  end
end.parse!

if options.onlyAmazon and options.notAmazon
  puts
  puts "-n and -a are mutually exclusive - use one or the other, not both"
  puts
  exit
end

if options.keywords.empty?
  puts
  puts "Please specify one or more keywords to search for (-k flag)"
  puts
  exit
end

if options.locations.empty?
  puts
  puts "Please specify one or more locations (-l flag)"
  puts
  exit
end

options.locations = options.locations.flatten.sort.uniq
options.keywords = options.keywords.flatten.sort.uniq.join(" ")

# p options
# exit

currentTime = epoch_current_time.strftime("%d %B %Y %T")
subject = "ESD Job Search Results (#{sbjct}) for #{currentTime}"  
jobsearch_file = epoch_current_time.strftime("esd-jobsearch-%d-%B-%Y-%H%M%S.html")
jobsearch_url = "http://www.lambard.net/jobsearch/esd/#{jobsearch_file}"

html_head = <<-HERE
<!DOCTYPE HTML>
<HTML>
<HEAD>
<META charset="UTF-8">
<!-- Required for Bootstrap/responsive content, probably won't hurt elsewhere -->
<META name="viewport" content="width=device-width, initial-scale=1.0">
<TITLE>Jobsearch Results</TITLE>
<script src="http://ajax.googleapis.com/ajax/libs/jquery/1.10.2/jquery.min.js"></script>
<script src="http://netdna.bootstrapcdn.com/bootstrap/3.0.2/js/bootstrap.min.js"></script>
<link rel="stylesheet" href="http://netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap.min.css">

<SCRIPT>
function toggle_description(reference) {
var selector = "#description_" + reference;
var theButton = "#button_" + reference;
if ($(selector).css('display') == 'block') {
$(selector).css('display','none'); 
//document.getElementById('button_${reference}').value='Show Description';
//$(theButton).val('Show Description');
$(theButton).text('Show Description');
}
else { 
$(selector).css('display','block');
//document.getElementById('button_${reference}').value='Hide Description';
//$(theButton).val('Hide Description');
$(theButton).text('Hide Description');
}
}

</SCRIPT>


<STYLE>

.wide_sep {
  height: 0px;
  width: 100%;
  border-bottom: 3px solid black;
  margin: 3px 0 5px 0;
}

.thin_sep {
  height: 0px;
  width: 100%;
  border-bottom: 1px solid black;
  margin: 3px 0 5px 0;
}

.lowest_score {
background-color: #999999;
}

.lowest_score_text {
background-color: #CCCCCC;
}

.low_score {
background-color: #FF3333;
}

.low_score_text {
background-color: #FF8080;
}

.middle_score {
background-color: #5C5CFF;
}

.middle_score_text {
background-color: #9999FF;
}

.high_score {
background-color: #33AD5C;
}

.high_score_text {
background-color: #80CC99;
}

.highest_score {
background-color: #D6AD33;
}

.highest_score_text {
background-color: #E6CC80;
}

.job_info_left {
  margin: 5px 0 0 5px;
}

.job_info_center {
  margin: 5px 0 0 0;
}

.job_info_right {
  margin: 5px 5px 0 0;
}

.esd_button {
margin: 5px;
background-color: #dddddd;
}

.jobtitle {
font-size: 1.2em;
color: black;
font-style: italic;
}

.description {
border-top: 2px solid;
font-size: 1em;
}

.clear {
clear: both;
}

.separator {
border-bottom: 4px solid;
margin: 4px 0 4px 0;
}

</STYLE>
</HEAD>

HERE

description_header = %q(<table border="0" bgColor="#F5F5F5" cellpadding="0" cellspacing="0" style="border-collapse: collapse" width="100%"><tr><td style="background-color: #CCCCCC;" nowrap="nowrap" width="100%">&nbsp;Description</td></tr></table>)

matcher = %r[<tr><td align="center" bgColor="#F5F5F5" nowrap valign="top">(.+?)</td><td align="left" bgColor="#F5F5F5" valign="top">(.+?)</td><td align="left" bgColor="#F5F5F5" valign="top"><a class="SearchResultLink" href="(.+?)">(.+?)</a></td><td align="center" bgColor="#F5F5F5" valign="top">(.+?)</td><td align="left" bgColor="#F5F5F5" valign="top">(.+?)</td><td align="left" bgColor="#F5F5F5" valign="top">(.+?)</td></tr>]

desc_regex = %r[<td align="left"><font style="font-size: 100%;">(.+?)</font></td>]

agent = Mechanize.new
agent.user_agent_alias = 'Mac Safari'
agent.log = Logger.new('esd.log')
agent.redirect_ok = true

data = {}

page = agent.get("#{base}/Employment.aspx")
form = page.form_with(:id => 'frmEmployment')

options.locations.each do |county|
  form['txtKeywords'] = options.keywords
  form['lstLocationCode'] = county.to_s
  form['lstONETMajorGroup'] = '0'
  form['keywordType'] = options.keywordType

  result = agent.submit(form, form.buttons[1])

  result_uri = result.uri.to_s
  result_uri.sub! /PageSize=25/, "PageSize=#{options.searchItems}"

  page = agent.get(result_uri)

  # jobs = page.links_with(href: /ShowJob/)
  # ap jobs

  content = page.content

  matches = content.scan(matcher)
  matches.each do |date, job_id, url, title, wtf, company, location|
    if options[:onlyAmazon]
      next if not company.match company_matcher
    end
    if options[:notAmazon]
      next if company.match company_matcher
    end
    if not options.alreadySeen
      if not already_seen.index(job_id).nil?
        next
      end
    end
    epoch_date = Date.parse(date).strftime('%s').to_i
    if (epoch_current_time - epoch_date).to_i >= options.age.to_i * 86400
      next
    end
    company.strip!
    title.strip!
    url = "#{base}/#{url}"
    description = ''

    detail_page = agent.get(url)
    detail_content = detail_page.content
    desc_matches = detail_content.match desc_regex
    if not desc_matches.nil?
      description = desc_matches[1]
      description.strip!
    end
    data[job_id] = [ date, job_id, url, title, company, location, description ]
  end
end

html_body = []
html_body <<  "<body>"
html_body <<  "<div class='container'>"
html_body <<  "  <div class='row'>"
html_body <<  "    <div class='col-xs-12'>"
html_body <<  "<div>Here are the results of today's job search. The parameters were:</div>"
html_body <<  "<p/>"
locs = []
options.locations.each do |loc|
  locs.push "#{locations[loc.to_i]} (#{loc})"
end
html_body <<  "<div>Location(s): #{locs.join ", "}</div>"
html_body <<  "<div>Age of postings: #{options.age} days</div>"
html_body <<  "<div>Search terms: #{options.keywords}</div>"
html_body <<  "<div>Keyword type: #{options.keywordType}</div>"
html_body <<  "<div>#{data.size} items</div>"
html_body <<  "<p/>"
html_body <<  "    </div>"
html_body <<  "  </div>"
html_body <<  "  <div class='row' style='border-bottom: 2px solid black;'></div>"
data.keys.each do |key|
  date, job_id, url, title, company, location, description = data[key]
  html_body << <<-EOF
  <div class="row">
    <div class="col-md-2 col-xs-6">
      #{date}
    </div>
    <div class="col-md-2 col-xs-6">
      #{job_id}
    </div>
    <div class="col-md-4 col-xs-12">
      <a href="#{url}">#{title}</a>
    </div>
    <div class="col-md-2 col-xs-6">
      #{company}
    </div>
    <div class="col-md-2 col-xs-6">
      #{location}
    </div>
    <hr>
    <div class="col-md-12 col-xs-12">
      #{description}
    </div>
  </div>
  <div class="row" style="border-bottom: 2px solid black;">
  <div class="row">
    <div class="col-md-12 col-xs-12">
      That's it for today. Happy hunting and good luck, starfighter!
    </div>
  </div>
</div>
EOF
end
html_body <<  "</div>"
html_body <<  "</body>"
html_body <<  "</html>"

mail_body = html_head + html_body.join("\n")

if options.testing
  puts mail_body
else
  mail = Mail.deliver do
    to      'Creede Lambard <clcareer@lambard.net>'
    from    'Jobsearch Engine <jobsearch@lambard.net>'
    subject "ESD job search results for #{epoch_current_time.to_s}"

    text_part do
      body "Check out the HTML section"
    end

    html_part do
      content_type 'text/html; charset=UTF-8'
      body mail_body
    end
  end

  data.keys.each do |key|
    redis.set(key, data[key])
  end
end



