require 'chef'
require 'erubis'
require 'tempfile'

namespace :ssl do
  desc "Initialize the OpenSSL CA"
  task :init do
    FileUtils.mkdir_p(SSL_CERT_DIR)
    FileUtils.mkdir_p(File.join(SSL_CA_DIR, "crl"))
    FileUtils.mkdir_p(File.join(SSL_CA_DIR, "newcerts"))
    FileUtils.touch(File.join(SSL_CA_DIR, "index"))

    b = binding()
    erb = Erubis::Eruby.new(File.read(SSL_CONFIG_FILE + ".erb"))

    File.open(SSL_CONFIG_FILE, "w") do |f|
      f.puts(erb.result(b))
    end

    unless File.exists?(File.join(SSL_CA_DIR, "serial"))
      File.open(File.join(SSL_CA_DIR, "serial"), "w") do |f|
        f.puts("01")
      end
    end

    unless File.exists?(File.join(SSL_CA_DIR, "crlnumber"))
      File.open(File.join(SSL_CA_DIR, "crlnumber"), "w") do |f|
        f.puts("01")
      end
    end

    unless File.exists?(File.join(SSL_CERT_DIR, "ca.crt"))
      subject =  "/C=#{SSL_COUNTRY_NAME}"
      subject += "/ST=#{SSL_STATE_NAME}"
      subject += "/L=#{SSL_LOCALITY_NAME}"
      subject += "/O=#{COMPANY_NAME}"
      subject += "/OU=#{SSL_ORGANIZATIONAL_UNIT_NAME}"
      subject += "/CN=Certificate Signing Authority"
      subject += "/emailAddress=#{SSL_EMAIL_ADDRESS}"
      sh("openssl req -config #{SSL_CONFIG_FILE} -new -nodes -x509 -days 3650 -subj '#{subject}' -newkey rsa:4096 -out #{SSL_CERT_DIR}/ca.crt -keyout #{SSL_CA_DIR}/ca.key")
      sh("openssl ca -config #{SSL_CONFIG_FILE} -gencrl -out #{SSL_CERT_DIR}/ca.crl")
    end

    chef_domain = URI.parse(Chef::Config[:chef_server_url]).host.
      split(".")[1..-1].join(".")

    if chef_domain != ""
      ENV['BATCH'] = "1"
      args = Rake::TaskArguments.new([:cn], ["*.#{chef_domain}"])
      Rake::Task["ssl:do_cert"].execute(args)
      knife :cookbook_upload, ["openssl", "--force"]
    end
  end

  task :do_cert => [ :init ]
  task :do_cert, :cn do |t, args|
    cn = args.cn
    keyfile = cn.gsub("*", "wildcard")

    FileUtils.mkdir_p(SSL_CERT_DIR)

    unless File.exist?(File.join(SSL_CERT_DIR, "#{keyfile}.key"))
      puts("** Creating SSL Certificate Request for #{cn}")

      b = binding()
      erb = Erubis::Eruby.new(File.read(File.join(TEMPLATES_DIR, 'openssl.cnf')))

      tf = Tempfile.new("#{keyfile}.ssl-conf")
      tf.puts(erb.result(b))
      tf.close

      if ENV['BATCH'] == "1"
        sh("openssl req -new -batch -nodes -config '#{tf.path}' -keyout #{SSL_CERT_DIR}/#{keyfile}.key -out #{SSL_CERT_DIR}/#{keyfile}.csr -newkey rsa:2048")
      else
        sh("openssl req -new -nodes -config '#{tf.path}' -keyout #{SSL_CERT_DIR}/#{keyfile}.key -out #{SSL_CERT_DIR}/#{keyfile}.csr -newkey rsa:2048")
      end
      sh("chmod 644 #{SSL_CERT_DIR}/#{keyfile}.key #{SSL_CERT_DIR}/#{keyfile}.csr")
    else
      puts("** SSL Certificate Request for #{cn} already exists, skipping.")
    end

    unless File.exist?(File.join(SSL_CERT_DIR, "#{keyfile}.crt"))
      puts("** Signing SSL Certificate Request for #{cn}")
      sh("openssl ca -config #{SSL_CONFIG_FILE} -batch -in #{SSL_CERT_DIR}/#{keyfile}.csr -out #{SSL_CERT_DIR}/#{keyfile}.crt")
      sh("chmod 644 #{SSL_CERT_DIR}/#{keyfile}.crt")
    else
      puts("** SSL Certificate for #{cn} already exists, skipping.")
    end

    if ENV['BATCH'] != "1" and not Process.euid == 0
      knife :cookbook_upload, ["openssl", "--force"]
    end
  end

  desc "Create a new SSL certificate"
  task :cert, :cn do |t, args|
    Rake::Task["ssl:do_cert"].execute(args)
  end

  task :create_missing_certs do
    old_batch = ENV['BATCH']
    ENV['BATCH'] = "1"

    Chef::Node.list.keys.each do |fqdn|
      args = Rake::TaskArguments.new([:cn], [fqdn])
      Rake::Task["ssl:do_cert"].execute(args)
    end

    ENV['BATCH'] = old_batch
    knife :cookbook_upload, ["openssl", "--force"]
  end

  desc "Revoke an existing SSL certificate"
  task :revoke, :cn do |t, args|
    keyfile = args.cn.gsub("*", "wildcard")
    sh("openssl ca -config #{SSL_CONFIG_FILE} -revoke #{SSL_CERT_DIR}/#{keyfile}.crt")
    sh("openssl ca -config #{SSL_CONFIG_FILE} -gencrl -out #{SSL_CERT_DIR}/ca.crl")
    sh("rm #{SSL_CERT_DIR}/#{keyfile}.{csr,crt,key}")
    knife :cookbook_upload, ['openssl', '--force']
  end

  desc "Renew expiring certificates"
  task :renew do
    old_batch = ENV['BATCH']
    ENV['BATCH'] = "1"

    Dir[SSL_CERT_DIR + "/*.crt"].each do |crt|
      %x(#{TOPDIR}/cookbooks/openssl/files/default/check_ssl_cert -n -c #{crt})
      if $?.exitstatus != 0
        fqdn = File.basename(crt).gsub(/\.crt$/, '')
        args = Rake::TaskArguments.new([:cn], [fqdn])
        Rake::Task["ssl:revoke"].execute(args)
        Rake::Task["ssl:do_cert"].execute(args)
      end
    end

    ENV['BATCH'] = old_batch
    knife :cookbook_upload, ["openssl", "--force"]
  end
end
