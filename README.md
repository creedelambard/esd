# esd
Scrape the Washington ESD website looking for jobs and mail the result to me

Usage: ruby esd.rb [options]
        --keywordType [TYPE]         Keyword type (rdoAll, rdoAny or rdoPhrase)
    -d, --age [DAYS]                 Maximum age in days
        --dupe                       Show items that have already been processed
    -l, --locations x,y,z            Locations to search (hint: 2100 is 'all of King County')
                                     Can specify more than once (e.g. '-l 2100 -l 4300')
    -k, --keywords x,y,z             Keywords to search for (e.g. 'ruby' or 'devops,ruby,rails')
                                     Can specify more than once (e.g. '-k ruby -k rails')
    -s, --searchItems=n              Number of items to search for (default 500)
    -n, --noAmazon                   Show only non-Amazon results
    -a, --onlyAmazon                 Show only Amazon results
    -t, --test                       Just do a dry run, don't send mail
    -h, --help                       Show this help message

Example:

ruby /home/creede/ruby/esd/esd.rb --keywordType "rdoAll" -l 2100 -l 4300 -d 2 -k ruby -k rails -k devops

  scrapes the ESD website for listings with all three keywords "ruby", "rails" and "devops" in King and
  Snohomish COunties within the last two days


