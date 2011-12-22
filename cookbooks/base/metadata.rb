description "This cookbook installs and configures the Gentoo base system"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.rst'))

maintainer "Benedikt Böhm"
maintainer_email "bb@xnull.de"
license "Apache v2.0"

depends "core_ext"
depends "git"
depends "hwraid"
depends "lftp"
depends "mdadm"
depends "munin"
depends "nagios"
depends "ntp"
depends "ohai"
depends "openssl"
depends "portage"
depends "shorewall"
depends "smart"
depends "tmux"
depends "vim"
