# Copyright 2014 Hewlett-Packard Development Company, L.P.
# Copyright 2015 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# == Class: stackalytics
#
class stackalytics (
  $stackalytics_ssh_private_key,
  $gerrit_ssh_user = 'stackalytics',
  $git_revision = 'master',
  $git_source = 'https://git.openstack.org/openstack/stackalytics',
  $memcached_port = '11211',
  $vhost_name = $::fqdn,
) {

  include ::httpd
  include ::httpd::mod::wsgi
  include ::pip

  $packages = [
    'libapache2-mod-proxy-uwsgi',
    'libapache2-mod-uwsgi',
    'uwsgi',
    'uwsgi-plugin-python',
  ]
  package { $packages:
    ensure => present,
  }

  class { '::memcached':
    # NOTE(pabelanger): current requirement is about 2.5Gb and it increases on
    # approx 0.5Gb per year
    max_memory => 4096,
    listen_ip  => '127.0.0.1',
    tcp_port   => $memcached_port,
    udp_port   => $memcached_port,
  }

  group { 'stackalytics':
    ensure => present,
  }

  user { 'stackalytics':
    ensure     => present,
    home       => '/home/stackalytics',
    shell      => '/bin/bash',
    gid        => 'stackalytics',
    managehome => true,
    require    => Group['stackalytics'],
  }

  file { '/home/stackalytics/.ssh':
    ensure  => directory,
    mode    => '0500',
    owner   => 'stackalytics',
    group   => 'stackalytics',
    require => User['stackalytics'],
  }

  file { '/home/stackalytics/.ssh/id_rsa':
    ensure  => present,
    content => $stackalytics_ssh_private_key,
    mode    => '0400',
    owner   => 'stackalytics',
    group   => 'stackalytics',
    require => File['/home/stackalytics/.ssh'],
  }

  file { '/var/lib/git':
    ensure  => directory,
    owner   => 'stackalytics',
    group   => 'stackalytics',
    mode    => '0644',
    require => User['stackalytics'],
  }

  vcsrepo { '/opt/stackalytics':
    ensure   => latest,
    provider => git,
    revision => $git_revision,
    source   => $git_source,
  }

  exec { 'install-stackalytics':
    command     => 'pip install /opt/stackalytics',
    path        => '/usr/local/bin:/usr/bin:/bin/',
    refreshonly => true,
    subscribe   => Vcsrepo['/opt/stackalytics'],
    notify      => Exec['stackalytics-reload'],
    require     => Class['pip'],
  }

  cron { 'process_stackalytics':
    user        => 'stackalytics',
    hour        => '*/4',
    command     => 'stackalytics-processor',
    environment => 'PATH=/usr/bin:/bin:/usr/sbin:/sbin',
    require     => Exec['install-stackalytics'],
  }

  file { '/etc/stackalytics':
    ensure => directory,
  }

  file { '/etc/stackalytics/stackalytics.conf':
    ensure  => present,
    owner   => 'stackalytics',
    mode    => '0444',
    content => file('/opt/stackalytics/etc/stackalytics.conf'),
    notify  => Exec['stackalytics-reload'],
    require => [
      File['/etc/stackalytics'],
      User['stackalytics'],
    ],
  }

  file { '/etc/uwsgi/apps-enabled/stackalytics.ini':
    ensure  => present,
    owner   => 'root',
    mode    => '0444',
    content => template('stackalytics/uwsgi.ini.erb'),
    notify  => Exec['stackalytics-reload'],
    require => [
      Package['uwsgi'],
    ],
  }

  exec { 'stackalytics-reload':
    command     => 'touch /usr/local/lib/python2.7/dist-packages/stackalytics/dashboard/web.wsgi',
    path        => '/usr/local/bin:/usr/bin:/bin/',
    refreshonly => true,
  }

  ::httpd::vhost { $vhost_name:
    port     => 80,
    docroot  => 'MEANINGLESS ARGUMENT',
    priority => '50',
    template => 'stackalytics/stackalytics.vhost.erb',
    ssl      => true,
  }

  httpd_mod { 'proxy':
    ensure => present,
  }

  httpd_mod { 'proxy_http':
    ensure => present,
  }

  httpd_mod { 'proxy_uwsgi':
    ensure => present,
  }

  ini_setting { 'sources_root':
    ensure  => present,
    notify  => Exec['stackalytics-reload'],
    path    => '/etc/stackalytics/stackalytics.conf',
    require => File['/etc/stackalytics/stackalytics.conf'],
    section => 'DEFAULT',
    setting => 'sources_root',
    value   => '/var/lib/git',
  }

  ini_setting { 'ssh_key_filename':
    ensure  => present,
    notify  => Exec['stackalytics-reload'],
    path    => '/etc/stackalytics/stackalytics.conf',
    require => File['/etc/stackalytics/stackalytics.conf'],
    section => 'DEFAULT',
    setting => 'ssh_key_filename',
    value   => '/home/stackalytics/.ssh/zuul.id_rsa',
  }

  ini_setting { 'ssh_username':
    ensure  => present,
    notify  => Exec['stackalytics-reload'],
    path    => '/etc/stackalytics/stackalytics.conf',
    require => File['/etc/stackalytics/stackalytics.conf'],
    section => 'DEFAULT',
    setting => 'ssh_username',
    value   => $gerrit_ssh_user,
  }
}
