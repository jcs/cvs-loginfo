#!/usr/bin/perl
# $Id: loginfo.pl,v 1.1 2004/04/05 01:37:23 jcs Exp $
# vim:ts=4
#
# loginfo.pl
# a cvs loginfo script to handle changelog writing and diff emailing,
# similar to the log_accum script included with cvs, but not nearly as
# hideous
#
# Copyright (c) 2004 joshua stein <jcs@rt.fm>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

#
# to process all subdirectories at once, this script will need to be called
# from commitinfo in "prep" mode (emulating commit_prep):
#  ALL $CVSROOT/CVSROOT/loginfo.pl -p
#
# then call the script normally from loginfo:
#  ALL perl $CVSROOT/CVSROOT/loginfo.pl -c $CVSROOT/CVSROOT/ChangeLog -d ${sVv}
#
# if the temporary file created in prep mode is not found, it will run once for
# every subdirectory
#

use strict;

my ($changelog, $dodiffs, $prepdir, $prepfile, $module, $branch);
my (@versions, @modfiles, @addfiles, @delfiles, @message, @log, @diffs);
my ($login, $gecos, $fullname, $email);

# temporary files used between runs
my $tmpdir = "/tmp";
my $tmp_lastdir = ".cvs.lastdir" . getpgrp();
my $tmp_modfiles = ".cvs.modfiles" . getpgrp();
my $tmp_addfiles = ".cvs.addfiles" . getpgrp();
my $tmp_delfiles = ".cvs.delfiles" . getpgrp();

# read command line args
while (@ARGV) {
	# check for prep mode
	if ($ARGV[0] eq "-p") {
		# the only args should be a directory and file
		$prepdir = $ARGV[1];
		$prepfile = $ARGV[2];
		last;
	}

	if ($ARGV[0] eq "-c") {
		$changelog = $ARGV[1];
		shift(@ARGV);
	} elsif ($ARGV[0] eq "-d") {
		$dodiffs = 1;
	} elsif ($ARGV[0] =~ /^(.+) - New directory$/) {
		# TODO
	} else {
		# read list of files, assuming a format of %{sVv}
		$ARGV[0] =~ /^(.*?) (.+)/;
		$module = $1;
		my $filelist = $2;

		# just take the basename
		$module = (split("/", $module))[0];

		# read list of changed files and their versions
		while ($filelist =~ /^(.+?,([\d\.]+|NONE),([\d\.]+|NONE))($| (.+))/) {
			push @versions, $1;
			$filelist = $5;
		}
	}
	shift(@ARGV);
}

if ($prepdir) {
	unlink($tmpdir . "/" . $tmp_lastdir);
	open(LASTDIR, ">" . $tmpdir . "/" . $tmp_lastdir) or
		die "can't prep to " . $tmpdir . "/" . $tmp_lastdir . ": " . $!;
	print LASTDIR $prepdir . "\n";
	close(LASTDIR);

	exit;
}

# read log message
my $startlog = my $startfiles = 0;
while (my $line = <STDIN>) {
	if ($line =~ /^Modified Files:/) {
		$startfiles = "m";
	} elsif ($line =~ /^Added Files:/) {
		$startfiles = "a";
	} elsif ($line =~ /^Removed Files:/) {
		$startfiles = "r";
	} elsif ($startfiles) {
		if ($line =~ /Tag: (.+)/) {
			$branch = $1;
		} elsif ($line =~ /^Log Message:/) {
			$startfiles = 0;
			$startlog++;
		} else {
			# a filename
			$line =~ s/^[ \t]+//;
			$line = "    " . $line;

			if ($startfiles eq "m") {
				push @modfiles, $line;
			} elsif ($startfiles eq "a") {
				push @addfiles, $line;
			} elsif ($startfiles eq "r") {
				push @delfiles, $line;
			}
		}
	} elsif ($startlog) {
		push @log, $line;
	}
}

# determine our user
if ($login = $ENV{"USER"}) {
	$gecos = (getpwnam($login))[6];
} else {
	($login, $gecos) = (getpwuid ($<))[0,6];
}
$fullname = $gecos;
$fullname =~ s/,.*//;
chop(my $hostname = `hostname`);
$email = $login . "\@" . $hostname;

# create the header
push @message, "CVSROOT:        " . $ENV{"CVSROOT"} . "\n";
push @message, "Module name:    " . $module . "\n";
if ($branch) {
	push @message, "Branch:         " . $branch . "\n";
}
my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
push @message, "Changes by:     " . $email . " "
	. sprintf("%02d/%02d/%02d %02d:%02d:%02d", ($year % 100), ($mon + 1),
		$mday, $hour, $min, $sec) . "\n";

push @message, "\n";

# add the list of files
if ($#modfiles > -1) {
	push @message, "Modified files:\n";
	foreach my $line (@modfiles) {
		push @message, $line;
	}
}
if ($#addfiles > -1) {
	push @message, "Added files:\n";
	foreach my $line (@addfiles) {
		push @message, $line;
	}
}
if ($#addfiles > -1) {
	push @message, "Removed files:\n";
	foreach my $line (@delfiles) {
		push @message, $line;
	}
}

push @message, "\n";

# add the log
push @message, "Log message:\n";
foreach my $line (@log) {
	push @message, "    " . $line;
}

# if we're saving to a changelog, do it now before we add the diffs
if ($changelog) {
	open(CHANGELOG, ">>" . $changelog) or
		warn "can't write to " . $changelog . ": " . $!;
	foreach my $line (@message) {
		print CHANGELOG $line;
	}
	close(CHANGELOG);
}

print "-----------------------------\n";
foreach my $line (@message) {
	print $line;
}

$dodiffs = 1;

if ($dodiffs) {
	# now generate diffs
	foreach my $file (@versions) {
		$file =~ /^(.+),([0-9\.]+|NONE),([0-9\.]+|NONE)$/;
		print "cvs rdiff -u -r" . $2 . " -r" . $3 . " " . $1 . "\n";
	}
}
