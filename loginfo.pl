#!/usr/bin/perl
# $Id: loginfo.pl,v 1.3 2004/04/05 16:17:07 jcs Exp $
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

# bucket o' variables
my ($changelog, $dodiffs, $prepdir, $prepfile, $lastdir, $module, $branch,
	$curdir);
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
		$module = (split("/", $1))[0];
		my $filelist = $2;

		# read list of changed files and their versions
		while ($filelist =~ /^(.+?,([\d\.]+|NONE),([\d\.]+|NONE))($| (.+))/) {
			push @versions, $1;
			$filelist = $5;
		}
	}
	shift(@ARGV);
}

if ($prepdir) {
	# if we're in prep dir, just record this as the last directory we've seen
	# and exit
	unlink($tmpdir . "/" . $tmp_lastdir);
	open(LASTDIR, ">" . $tmpdir . "/" . $tmp_lastdir) or
		die "can't prep to " . $tmpdir . "/" . $tmp_lastdir . ": " . $!;
	print LASTDIR $prepdir . "\n";
	close(LASTDIR);

	exit;
}

# else, we're in loginfo mode, so read the last directory prep mode found
open(LASTDIR, "<" . $tmpdir . "/" . $tmp_lastdir) or
	die "can't read " . $tmpdir . "/" . $tmp_lastdir . ": " . $!;
chop($lastdir = <LASTDIR>);
close(LASTDIR);

# read log message
my $startlog = my $startfiles = 0;
while (my $line = <STDIN>) {
	if ($startfiles) {
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

		# specifying 'nodiff' in the cvs log will disable sending diffs for
		# this commit, useful if the commit includes sensitive information or
		# if the diff will be huge
		if ($line =~ /nodiff/i) {
			$dodiffs = 0;
		}
	} else {
		if ($line =~ /^Update of (.+)/) {
			$curdir = $1;
		} elsif ($line =~ /^Modified Files:/) {
			$startfiles = "m";
		} elsif ($line =~ /^Added Files:/) {
			$startfiles = "a";
		} elsif ($line =~ /^Removed Files:/) {
			$startfiles = "r";
		}
	}
}

if ($curdir eq $lastdir) {
	# this is the last time we will run in loginfo mode, read the previous
	# lists of files
	if (-f $tmpdir . "/" . $tmp_modfiles) {
		open(MODFILES, "<" . $tmpdir . "/" . $tmp_modfiles) or
			die "can't read from " . $tmpdir . "/" . $tmp_modfiles . ": " . $!;
		while (my $line = <MODFILES>) {
			push @modfiles, $line;
		}
		close(MODFILES);
	}
	if (-f $tmpdir . "/" . $tmp_addfiles) {
		open(ADDFILES, "<" . $tmpdir . "/" . $tmp_addfiles) or
			die "can't read from " . $tmpdir . "/" . $tmp_addfiles . ": " . $!;
		while (my $line = <ADDFILES>) {
			push @addfiles, $line;
		}
		close(ADDFILES);
	}
	if (-f $tmpdir . "/" . $tmp_addfiles) {
		open(DELFILES, "<" . $tmpdir . "/" . $tmp_delfiles) or
			die "can't read from " . $tmpdir . "/" . $tmp_delfiles . ": " . $!;
		while (my $line = <DELFILES>) {
			push @delfiles, $line;
		}
		close(DELFILES);
	}
} else {
	# we have more directories to process, just record what we saw here and
	# exit
	if ($#modfiles > -1) {
		open(MODFILES, ">>" . $tmpdir . "/" . $tmp_modfiles) or
			die "can't append to " . $tmpdir . "/" . $tmp_modfiles . ": " . $!;
		foreach my $modfile (@modfiles) {
			print MODFILES $modfile;
		}
		close(MODFILES);
	}
	if ($#addfiles > -1) {
		open(ADDFILES, ">>" . $tmpdir . "/" . $tmp_addfiles) or
			die "can't append to " . $tmpdir . "/" . $tmp_addfiles . ": " . $!;
		foreach my $addfile (@addfiles) {
			print ADDFILES $addfile;
		}
		close(ADDFILES);
	}
	if ($#delfiles > -1) {
		open(DELFILES, ">>" . $tmpdir . "/" . $tmp_delfiles) or
			die "can't append to " . $tmpdir . "/" . $tmp_delfiles . ": " . $!;
		foreach my $delfile (@delfiles) {
			print DELFILES $delfile;
		}
		close(DELFILES);
	}

	exit;
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
