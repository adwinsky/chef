# triggers for other resources
execute "systemd-reload" do
  command "systemctl --system daemon-reload"
  action :nothing
  only_if { systemd_running? }
end

execute "systemd-tmpfiles" do
  command "systemd-tmpfiles --create"
  action :nothing
  only_if { systemd_running? }
end

case node[:platform]
when "gentoo"
  if root?
    portage_package_keywords "~sys-apps/dbus-1.6.8"
    portage_package_keywords "~sys-apps/systemd-197"

    package "sys-apps/systemd"

    node.default[:portage][:USE] += %w(systemd)

    # by default, boot into multi-user.target
    service "multi-user.target" do
      action :enable
      provider Chef::Provider::Service::Systemd
    end

    template "/etc/systemd/system.conf" do
      source "system.conf"
      owner "root"
      group "root"
      mode "0644"
    end

    # journal
    template "/etc/systemd/journald.conf" do
      source "journald.conf"
      owner "root"
      group "root"
      mode "0644"
    end

    # networking
    file "/etc/hostname" do
      content "#{node[:hostname]}\n"
      owner "root"
      group "root"
      mode "0644"
    end

    link "/etc/ifup" do
      to "/etc/ifup.eth0"
      only_if { File.exist?("/etc/ifup.eth0") }
    end

    file "/etc/ifup" do
      owner "root"
      group "root"
      mode "0644"
    end

    file "/etc/ifdown" do
      owner "root"
      group "root"
      mode "0644"
    end

    systemd_unit "network.service"

    service "network.service" do
      action :enable
      provider Chef::Provider::Service::Systemd
    end

    service "sshd.service" do
      action :enable
      provider Chef::Provider::Service::Systemd
    end

    # user session support
    systemd_unit "user-session@.service"

    nagios_plugin "check_systemd"
  end
end