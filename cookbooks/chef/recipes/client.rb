if gentoo?
  package "app-admin/chef"
end

directory "/etc/chef" do
  owner "root"
  group "root"
  mode "0755"
end

file "/etc/chef/client.pem" do
  owner "root"
  group "root"
  mode "0400"
end

template "/etc/chef/client.rb" do
  source "client.rb"
  owner "root"
  group "root"
  mode "0644"
end

template "/etc/chef/knife.rb" do
  source "client.rb"
  owner "root"
  group "root"
  mode "0644"
end

directory "/var/log/chef" do
  owner "root"
  group "root"
  mode "0755"
end

directory "/var/lib/chef" do
  owner "root"
  group "root"
  mode "0750"
end

directory "/var/lib/chef/cache" do
  owner "root"
  group "root"
  mode "0750"
end

timer_envs = %w(production staging)

nodes = chef_client_nodes.map do |n|
  n[:fqdn]
end

minutes = nodes.each_with_index.map do |_, idx|
  (idx * (60.0 / nodes.length)).to_i
end

index = nodes.index(node[:fqdn])
minute = minutes[index] rescue 0

cron "chef-client" do
  command "/usr/bin/ruby -E UTF-8 #{node[:chef][:binary]} -c /etc/chef/client.rb &>/dev/null"
  minute minute
  action :delete unless timer_envs.include?(node.chef_environment)
  action :delete if systemd_running?
end

systemd_unit "chef-client.service"

systemd_timer "chef-client" do
  schedule [
    "OnBootSec=60",
    "OnCalendar=*:#{minute}",
  ]
end

# chef-client.service has a condition on this lock
# so we use it to stop chef-client on testing/staging machines
file "/run/lock/chef-client.lock" do
  action :delete if timer_envs.include?(node.chef_environment)
end

directory "/etc/chef/cache" do
  action :delete
  recursive true
  only_if { File.directory?("/etc/chef/cache") and not File.symlink?("/etc/chef/cache") }
end

link "/etc/chef/cache" do
  to "/var/lib/chef/cache"
end
