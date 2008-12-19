require 'digest/md5'

module ActionController # :nodoc:
  # Represents an HTTP response generated by a controller action. One can use an
  # ActionController::AbstractResponse object to retrieve the current state of the
  # response, or customize the response. An AbstractResponse object can either
  # represent a "real" HTTP response (i.e. one that is meant to be sent back to the
  # web browser) or a test response (i.e. one that is generated from integration
  # tests). See CgiResponse and TestResponse, respectively.
  #
  # AbstractResponse is mostly a Ruby on Rails framework implement detail, and should
  # never be used directly in controllers. Controllers should use the methods defined
  # in ActionController::Base instead. For example, if you want to set the HTTP
  # response's content MIME type, then use ActionControllerBase#headers instead of
  # AbstractResponse#headers.
  #
  # Nevertheless, integration tests may want to inspect controller responses in more
  # detail, and that's when AbstractResponse can be useful for application developers.
  # Integration test methods such as ActionController::Integration::Session#get and
  # ActionController::Integration::Session#post return objects of type TestResponse
  # (which are of course also of type AbstractResponse).
  #
  # For example, the following demo integration "test" prints the body of the
  # controller response to the console:
  #
  #  class DemoControllerTest < ActionController::IntegrationTest
  #    def test_print_root_path_to_console
  #      get('/')
  #      puts @response.body
  #    end
  #  end
  class AbstractResponse
    DEFAULT_HEADERS = { "Cache-Control" => "no-cache" }
    attr_accessor :request

    attr_accessor :status
    # The body content (e.g. HTML) of the response, as a String.
    attr_accessor :body
    # The headers of the response, as a Hash. It maps header names to header values.
    attr_accessor :headers
    attr_accessor :session, :cookies, :assigns, :template, :layout
    attr_accessor :redirected_to, :redirected_to_method_params

    delegate :default_charset, :to => 'ActionController::Base'

    def initialize
      @body, @headers, @session, @assigns = "", DEFAULT_HEADERS.merge("cookie" => []), [], []
    end

    def location; headers['Location'] end
    def location=(url) headers['Location'] = url end


    # Sets the HTTP response's content MIME type. For example, in the controller
    # you could write this:
    #
    #  response.content_type = "text/plain"
    #
    # If a character set has been defined for this response (see charset=) then
    # the character set information will also be included in the content type
    # information.
    def content_type=(mime_type)
      self.headers["Content-Type"] =
        if mime_type =~ /charset/ || (c = charset).nil?
          mime_type.to_s
        else
          "#{mime_type}; charset=#{c}"
        end
    end

    # Returns the response's content MIME type, or nil if content type has been set.
    def content_type
      content_type = String(headers["Content-Type"] || headers["type"]).split(";")[0]
      content_type.blank? ? nil : content_type
    end

    # Set the charset of the Content-Type header. Set to nil to remove it.
    # If no content type is set, it defaults to HTML.
    def charset=(charset)
      headers["Content-Type"] =
        if charset
          "#{content_type || Mime::HTML}; charset=#{charset}"
        else
          content_type || Mime::HTML.to_s
        end
    end

    def charset
      charset = String(headers["Content-Type"] || headers["type"]).split(";")[1]
      charset.blank? ? nil : charset.strip.split("=")[1]
    end

    def last_modified
      if last = headers['Last-Modified']
        Time.httpdate(last)
      end
    end

    def last_modified?
      headers.include?('Last-Modified')
    end

    def last_modified=(utc_time)
      headers['Last-Modified'] = utc_time.httpdate
    end

    def etag
      headers['ETag']
    end
    
    def etag?
      headers.include?('ETag')
    end
    
    def etag=(etag)
      if etag.blank?
        headers.delete('ETag')
      else
        headers['ETag'] = %("#{Digest::MD5.hexdigest(ActiveSupport::Cache.expand_cache_key(etag))}")
      end
    end

    def redirect(url, status)
      self.status = status
      self.location = url.gsub(/[\r\n]/, '')
      self.body = "<html><body>You are being <a href=\"#{CGI.escapeHTML(url)}\">redirected</a>.</body></html>"
    end

    def sending_file?
      headers["Content-Transfer-Encoding"] == "binary"
    end

    def assign_default_content_type_and_charset!
      self.content_type ||= Mime::HTML
      self.charset ||= default_charset unless sending_file?
    end

    def prepare!
      assign_default_content_type_and_charset!
      handle_conditional_get!
      set_content_length!
      convert_content_type!
    end

    private
      def handle_conditional_get! 
        if etag? || last_modified? 
          set_conditional_cache_control! 
        elsif nonempty_ok_response? 
          self.etag = body 

          if request && request.etag_matches?(etag) 
            self.status = '304 Not Modified' 
            self.body = '' 
          end 

          set_conditional_cache_control! 
        end 
      end

      def nonempty_ok_response?
        ok = !status || status.to_s[0..2] == '200'
        ok && body.is_a?(String) && !body.empty?
      end

      def set_conditional_cache_control!
        if headers['Cache-Control'] == DEFAULT_HEADERS['Cache-Control']
          headers['Cache-Control'] = 'private, max-age=0, must-revalidate'
        end
      end

      def convert_content_type!
        if content_type = headers.delete("Content-Type")
          self.headers["type"] = content_type
        end
        if content_type = headers.delete("Content-type")
          self.headers["type"] = content_type
        end
        if content_type = headers.delete("content-type")
          self.headers["type"] = content_type
        end
      end
    
      # Don't set the Content-Length for block-based bodies as that would mean reading it all into memory. Not nice
      # for, say, a 2GB streaming file.
      def set_content_length!
        unless body.respond_to?(:call) || (status && status.to_s[0..2] == '304')
          self.headers["Content-Length"] ||= body.size
        end
      end
  end
end
