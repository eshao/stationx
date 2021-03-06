# Helper functions.
def pputs(str); $server.prefix += str.to_s + "\n"; end
def sputs(str); $server.suffix += str.to_s + "\n"; end
def oputs(str); $server.opt += str.to_s + "\n"; end

def redirect(to)
  oputs <<-eos
  rewrite ^/(.*) #{to}/$1 permanent;
  eos
end

def redirh(to)
  redir("http://#{to}")
end

# As per https://github.com/ioerror/duraconf
def ssl(crt, key)
  oputs <<-eos
  ssl on;
  ssl_certificate     #{crt};
  ssl_certificate_key #{key};
  # Only strong ciphers in PFS mode
  ssl_ciphers DHE-RSA-AES256-SHA:DHE-DSS-AES256-SHA:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA;
  ssl_protocols SSLv3 TLSv1;
  # SSL optimizations
  ssl_session_cache   shared:SSL:10m;
  ssl_session_timeout 10m;
  eos
end

def password(htaccess)
  oputs <<-eos
  auth_basic "Restricted";
  auth_basic_user_file #{htaccess};
  eos
end

# Sends requests to index.php?q=(req) for WP.
def index_redir(base)
  oputs <<-eos
  if (-f $request_filename) { break; }
  if (-d $request_filename) { break; }
  rewrite ^(.+)$ #{base}$1 last;
  eos
end

def rename(req, loc)
  oputs <<-eos
  location #{req} {
    alias #{loc};
  }
  eos
end

# Disable auto index on a location
def autoindex(loc, switch = 'on')
  oputs <<-eos
  location #{loc} {
    autoindex #{switch};
  }
  eos
end

# No spidering
def no_spider
  oputs <<-eos
  location /robots.txt {
    alias /usr/local/etc/nginx/robots.txt;
  }
  eos
end

#######################################################################
#
#
# Four major scripting languages.
#
#
def php
  oputs <<-eos
  location ~ \.php$ {
    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $root_pub/$subdomain/$fastcgi_script_name;
    include /etc/nginx/fastcgi_params;
  }
  eos
end
def py
  oputs <<-eos
  location ~ \.py$ {
    proxy_pass       http://localhost:8080/$rel_root_pub/$subdomain/$uri;
    proxy_set_header Host $host;
  }
  eos
end
def rb
  oputs <<-eos
  location ~ \.rb$ {
    proxy_pass       http://localhost:8080/$rel_root_pub/$subdomain/$uri;
    proxy_set_header Host $host;
  }
  eos
end
def pl
  oputs <<-eos
  location ~ \.pl$ {
    proxy_pass       http://localhost:8080/$rel_root_pub/$subdomain/$uri;
    proxy_set_header Host $host;
  }
  eos
end
def pppr
  php; py; pl; rb
end

########################################################################
#
#
# Application-specific configurations.
#
#
def doku
  oputs <<-eos
  rewrite ^(/)_media/(.*)          $1lib/exe/fetch.php?media=$2  last;
  rewrite ^(/)_detail/(.*)         $1lib/exe/detail.php?media=$2 last;
  rewrite ^(/)_export/([^/]+)/(.*) $1doku.php?do=export_$2&id=$3 last;

  location / {
    if (!-f $request_filename) {
      rewrite ^(/)(.*)?(.*)  $1doku.php?id=$2&$3 last;
      rewrite ^(/)$ $1doku.php last;
    }
  }
  eos
end

def mailman
  oputs <<-eos
  # Show in the main page the list info
  rewrite ^/$ /mailman/listinfo permanent;

  location /mailman/ {
    # Use thttpd for CGI
    proxy_pass http://localhost:8080/mailman/;

    proxy_set_header Host $host;
    #proxy_intercept_errors on;
  }

  location /icons/ {
    alias /usr/local/mailman/icons/;
  }

  location /pipermail/ {
    alias /usr/local/mailman/archives/public/;
  }
  eos
end

# Proxy to some backend.
def proxy(port, num = 1, location = '/')
  pputs "upstream #{$server.name}_#{port}_cluster {"
  num.times {|i| pputs "  server 127.0.0.1:#{port+i};"}
  pputs "}\n"

  oputs <<-eos
  location #{location} {
    proxy_pass http://#{$server.name}_#{port}_cluster;
    proxy_redirect off;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
  eos
end

# fcgi to some backend.
def fcgi(port, additional = '')
  oputs <<-eos
  location / {
    fastcgi_pass  127.0.0.1:#{port};
    fastcgi_param SCRIPT_FILENAME $root_pub/$subdomain/$fastcgi_script_name;
    include       /etc/nginx/fastcgi_params;
    #{additional}
  }
  eos
end

# Remember to cap deploy && cap deploy:start
def rails(port, num)
  pputs "upstream #{port}_cluster {"
  num.times {|i| pputs "  server 127.0.0.1:#{port+i};"}
  pputs "}\n"

  oputs <<-eos
  location / {
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_redirect off;

    if (-f $request_filename/index.html) {
      rewrite (.*) $1/index.html break;
    }

    if (-f $request_filename.html) {
      rewrite (.*) $1.html break;
    }

    if (!-f $request_filename) {
      proxy_pass http://#{port}_cluster;
      break;
    }
  }
  eos
end
