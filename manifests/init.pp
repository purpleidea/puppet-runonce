# Simple runonce module by James
# Copyright (C) 2012-2013+ James Shubin
# Written by James Shubin <james@shubin.ca>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

class runonce::vardir {	# module vardir snippet
	if "${::puppet_vardirtmp}" == '' {
		if "${::puppet_vardir}" == '' {
			# here, we require that the puppetlabs fact exist!
			fail('Fact: $puppet_vardir is missing!')
		}
		$tmp = sprintf("%s/tmp/", regsubst($::puppet_vardir, '\/$', ''))
		# base directory where puppet modules can work and namespace in
		file { "${tmp}":
			ensure => directory,	# make sure this is a directory
			recurse => false,	# don't recurse into directory
			purge => true,		# purge all unmanaged files
			force => true,		# also purge subdirs and links
			owner => root,
			group => nobody,
			mode => 600,
			backup => false,	# don't backup to filebucket
			#before => File["${module_vardir}"],	# redundant
			#require => Package['puppet'],	# no puppet module seen
		}
	} else {
		$tmp = sprintf("%s/", regsubst($::puppet_vardirtmp, '\/$', ''))
	}
	$module_vardir = sprintf("%s/runonce/", regsubst($tmp, '\/$', ''))
	file { "${module_vardir}":		# /var/lib/puppet/tmp/runonce/
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		require => File["${tmp}"],	# File['/var/lib/puppet/tmp/']
	}
}

class runonce() {
#	include runonce::vardir
#	#$vardir = $::runonce::vardir::module_vardir	# with trailing slash
#	$vardir = regsubst($::runonce::vardir::module_vardir, '\/$', '')
}

# don't include this class yourself! it is meant to be called by runonce::reboot
class runonce::reboot::exec(
	$time,
	$message
) {
	include runonce
	include runonce::vardir
	#$vardir = $::runonce::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::runonce::vardir::module_vardir, '\/$', '')

	exec { "/bin/date >> ${vardir}/reboot && /sbin/shutdown -r ${time} ${message}":
		creates => "${vardir}/reboot",	# run once
		#stage => shutdown,	# NOTE: this has to be placed at class level
		require => File["${vardir}/"],
	}
}

# XXX: runonce::reboot is untested!
# FIXME: it would be good to only run this if puppet successfully worked (or
# only stopped rebooting when puppet fully 'ran without errors')
class runonce::reboot(
	$time = 'now',	# +5 or hh:mm is acceptable too
	$message = 'Puppet is triggering a reboot'
) {
	stage { 'shutdown':
		require => Stage['last'],
	}

	class { 'runonce::reboot::exec':
		time => $time,
		message => $message,
		stage => shutdown,
	}
}

class runonce::exec::base {
	include runonce::vardir
	#$vardir = $::runonce::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::runonce::vardir::module_vardir, '\/$', '')

	file { "${vardir}/exec/":
		ensure => directory,		# make sure this is a directory
		recurse => false,		# recursively manage directory
		purge => false,			# purge all unmanaged files
		force => false,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		require => File["${vardir}/"],
	}
}

# FIXME: Warning: notify is a metaparam; this value will inherit to all
# contained resources in the runonce::timer definition
define runonce::exec(
	$command = '/bin/true',
	$notify = undef,
	$repeat_on_failure = true
) {
	include runonce::exec::base
	include runonce::vardir
	#$vardir = $::runonce::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::runonce::vardir::module_vardir, '\/$', '')

	$date = "/bin/date >> ${vardir}/exec/${name}"
	$valid_command = $repeat_on_failure ? {
		false => "${date} && ${command}",
		default => "${command} && ${date}",
	}

	exec { "runonce-exec-${name}":
		command => "${valid_command}",
		creates => "${vardir}/exec/${name}",	# run once
		notify => $notify,
		# TODO: add any other parameters here that users wants such as cwd and environment...
		require => File["${vardir}/exec/"],
	}
}

class runonce::timer::base {
	include runonce
	include runonce::vardir
	#$vardir = $::runonce::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::runonce::vardir::module_vardir, '\/$', '')

	file { "${vardir}/start/":
		ensure => directory,		# make sure this is a directory
		recurse => false,		# recursively manage directory
		purge => false,			# purge all unmanaged files
		force => false,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		require => File["${vardir}/"],
	}

	file { "${vardir}/timer/":
		ensure => directory,		# make sure this is a directory
		recurse => false,		# recursively manage directory
		purge => false,			# purge all unmanaged files
		force => false,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		require => File["${vardir}/"],
	}
}

# when this is first run by puppet, a "timestamp" matching the system clock is
# saved. every time puppet runs (usually every 30 minutes) it compares the
# timestamp to the current time, and if this difference exceeds that of the
# set delta, then the requested command is executed.
# FIXME: Warning: notify is a metaparam; this value will inherit to all
# contained resources in the runonce::timer definition
define runonce::timer(
	$command = '/bin/true',
	$delta = 3600,				# seconds to wait...
	$notify = undef,
	$repeat_on_failure = true,
	$again = true				# use a timed Exec['again']
) {
	include runonce::timer::base
	include runonce::vardir
	if $again {
		include common::again
	}

	#$vardir = $::runonce::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::runonce::vardir::module_vardir, '\/$', '')

	# start the timer...
	exec { "/bin/date > ${vardir}/start/${name}":
		creates => "${vardir}/start/${name}",	# run once
		notify => [
			Exec["runonce-timer-${name}"],
			Common::Again::Delta["runonce-timer-${name}"],	# magic
		],
		require => File["${vardir}/start/"],
		alias => "runonce-start-${name}",
	}

	if $again {
		# this will cause puppet to run again after this delta is up...
		common::again::delta { "runonce-timer-${name}":
			delta => $delta,
		}
	}

	$date = "/bin/date >> ${vardir}/timer/${name}"
	$valid_command = $repeat_on_failure ? {
		false => "${date} && ${command}",
		default => "${command} && ${date}",
	}

	# end the timer and run command (or vice-versa)
	exec { "runonce-timer-${name}":
		command => "${valid_command}",
		creates => "${vardir}/timer/${name}",	# run once
		# NOTE: run if the difference between the current date and the
		# saved date (both converted to sec) is greater than the delta
		onlyif => "/usr/bin/test -e ${vardir}/start/${name} && /usr/bin/test \$(( `/bin/date +%s` - `/usr/bin/head -n 1 ${vardir}/start/${name} | /bin/date --file=- +%s` )) -gt ${delta}",
		notify => $notify,
		require => [
			File["${vardir}/timer/"],
			Exec["runonce-start-${name}"],
		],
		# TODO: add any other parameters here that users wants such as cwd and environment...
	}
}

