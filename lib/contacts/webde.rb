require "iconv"

class Contacts
  class Webde < Base
    LOGIN_URL = "https://login.web.de/intern/login/"
    JUMP_URL = "https://uas2.uilogin.de/intern/jump/"
    ADDRESSBOOK_URL = "https://adressbuch.web.de/exportcontacts"
    FOLDER_URL = "https://freemailng0101.web.de/online/ordner/"
    MENU_URL = "https://freemailng0101.web.de/online/menu.htm"
    
    def initialize(*args)
      super
      @contacts = Set.new
    end
    
    def real_connect
      postdata = "service=freemail&server=%s&password=%s&username=%s" % [
        CGI.escape('https://freemail.web.de'),
        CGI.escape(password),
        CGI.escape(login)
      ]

      # send login
      data, resp, cookies, forward = post(LOGIN_URL, postdata)

      if forward.include?("logonfailed")
        raise AuthenticationError, "Username and password do not match"
      end

      # request session from login service
      data, resp, cookies, forward = get forward

      # start mail app session
      data, resp, cookies, forward = get forward

      @si = forward.match(/si=([^&]+)/)[1]
    end

    def connected?
      @si && @si.length > 0
    end

    def contacts
      get_entries_from_folders
      connect_to_addressbook
      if @sessionid
        CSV.parse(get_entries_from_addressbook) do |row|
          @contacts << [latin1_to_utf8("#{row[2]} #{row[0]}"), latin1_to_utf8(row[9])] unless header_row?(row)
        end
      end
      
      @contacts
    end

    private
   
    def latin1_to_utf8(string)
      Iconv.conv("utf-8", "ISO-8859-1", string)
    end
    
    def header_row?(row)
      row[0] == 'Nachname'
    end
    
    def get_entries_from_folders
      folder_links.each do |link|
        begin  
          page = folder_page(link)
          scan_page_for_contacts(page)
          link = next_page_link(page)
        end while link && @contacts.length < 100
      end
    end
    
    def next_page_link(page)
      match = page.match(/<a id="oneforward"[^>]*href="\.\.\/ordner\/([^"]+)">/)
      match and match[1]
    end
    
    def scan_page_for_contacts(page)
      page.scan(/title="&#34;([^#]+)&#34; <([^>]+)>">/) do |match|
        @contacts << [match[0], match[1]]
      end
    end
    
    
    def folder_page(link)
      folder_page, resp, cookies, forward = get FOLDER_URL + link
      folder_page
    end
    
    
    def folder_links
      folder_names = %w(-Freunde Gesendet)
      menu, resp, cookies, forward = get "#{MENU_URL}?si=#{@si}"      
      folder_names.map do |folder_name|
        menu.match(/<option value="ordner\/([^"]+)"><span>#{folder_name}[^<]*<\/span><\/option>/)[1]
      end
    end

    def connect_to_addressbook
      data, resp, cookies, forward = get JUMP_URL + "?serviceID=comsaddressbook-live.webde&session=#{@si}&server=https://freemailng2901.web.de&partnerdata="
      @sessionid = forward.match(/session=([^&]+)/)[1]
    end
    
    def get_entries_from_addressbook 
      postdata = "language=de&raw_format=csv_Outlook2003&session=#{@sessionid}&what=PERSON"
      data, resp, cookies, forward = post ADDRESSBOOK_URL, postdata
      data
    end
  end
  
  TYPES[:webde] = Webde
end