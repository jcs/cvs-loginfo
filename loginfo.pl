#!/usr/bin/perl
# $Id: loginfo.pl,v 1.10 2004/11/19 18:18:41 jcs Exp $
# vim:ts=4
#
# loginfo.pl
#
# a cvs loginfo script to handle changelog writing and emailing, similar to
# the log_accum script included with cvs, but not nearly as hideous.  also
# supports emailing diffs.
#
# Copyright (c) 2004 joshua stein <jcs@jcs.org>
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
#  ALL  $CVSROOT/CVSROOT/loginfo.pl -p
#
# then call the script normally from loginfo:
#  ALL  perl $CVSROOT/CVSROOT/loginfo.pl -c $CVSROOT/CVSROOT/ChangeLog \
#             -m somelist@example.com -d ${sVv}
#

use strict;

# bucket o' variables
my ($changelog, $dodiffs, $donewdir, $doimport, $doemail);
my ($curdir, $prepdir, $lastdir, $module, $branch);
my (@diffcmds, %modfiles, %addfiles, %delfiles, @message, @log);

# temporary files used between runs
my $tmpdir = "/tmp";
my $tmp_lastdir = ".cvs.lastdir" . getpgrp();
my $tmp_modfiles = ".cvs.modfiles" . getpgrp();
my $tmp_addfiles = ".cvs.addfiles" . getpgrp();
my $tmp_delfiles = ".cvs.delfiles" . getpgrp();
my $tmp_diffcmd = ".cvs.diffcmd" . getpgrp();

# read command line args
while (@ARGV) {
	# check for prep mode
	if ($ARGV[0] eq "-p") {
		# the only args should be a directory (and a file we don't use)
		$prepdir = $ARGV[1];

		# remove the cvsroot and slash
		$prepdir = substr($prepdir, length($ENV{"CVSROOT"}) + 1);

		last;
	}

	# configuration options
	elsif ($ARGV[0] eq "-c") {
		$changelog = $ARGV[1];
		shift(@ARGV);
	} elsif ($ARGV[0] eq "-d") {
		$dodiffs = 1;
	} elsif ($ARGV[0] eq "-m") {
		$doemail = $ARGV[1];
		shift(@ARGV);
	}

	# args passed by cvs
	elsif ($ARGV[0] =~ /^(.+) - New directory$/) {
		$donewdir = $1;

		if ($donewdir =~ /^(.+?)\/(.+)/) {
			$module = $1;
			$donewdir = $2;
		}

		last;
	} elsif ($ARGV[0] =~ /^(.+) - Imported sources$/) {
		$doimport = $1;

		if ($doimport =~ /^(.+?)\/(.+)/) {
			$module = $1;
			$doimport = $2;
		}

		last;
	} else {
		# read list of files, assuming a format of %{sVv} giving us:
		# something/here/blah file1,1.1,1.2 file2,NONE,1.3

		$ARGV[0] =~ /^(.+?) (.+)/;

		# our "module" is the first component of the path
		$module = (split("/", $1))[0];

		# and our current directory is the rest of the path
		$curdir = (split("/", $1, 2))[1];
		if ($curdir eq "") {
			$curdir = ".";
		}

		# our files are the second part of argv[0]
		my $filelist = $2;

		# init
		@{$modfiles{$curdir}} = ();
		@{$addfiles{$curdir}} = ();
		@{$delfiles{$curdir}} = ();

		# read list of changed files and their versions
		while ($filelist =~ /^((.+?),([\d\.]+|NONE),([\d\.]+|NONE))($| (.+))/) {
			$filelist = $6;

			if ($3 eq "NONE") {
				push @{$addfiles{$curdir}}, $2;
			} elsif ($4 eq "NONE") {
				push @{$delfiles{$curdir}}, $2;
			} else {
				push @{$modfiles{$curdir}}, $2;
				push @diffcmds, "-r" . $3 . " -r" . $4 . " " . $module . "/"
					. ($curdir eq "." ? "" : $curdir . "/") . $2;
			}
		}
	}
	shift(@ARGV);
}

if ($prepdir) {
	# if we're in prep dir, just record this as the last directory we've seen
	# and exit
	unlink($tmpdir . "/" . $tmp_lastdir);

	# XXX: this is not safe
	open(LASTDIR, ">" . $tmpdir . "/" . $tmp_lastdir) or
		die "can't prep to " . $tmpdir . "/" . $tmp_lastdir . ": " . $!;
	print LASTDIR $prepdir . "\n";
	close(LASTDIR);

	exit;
}

if ($donewdir eq "") {
	if ($doimport eq "") {
		# we're in loginfo mode, so read the last directory prep mode found
		open(LASTDIR, "<" . $tmpdir . "/" . $tmp_lastdir) or
			die "can't read " . $tmpdir . "/" . $tmp_lastdir . ": " . $!;
		chop($lastdir = <LASTDIR>);
		close(LASTDIR);
	}

	# read log message
	my $startlog = 0;
	while (my $line = <STDIN>) {
		if ($startlog) {
			push @log, $line;

			# specifying 'nodiff' in the cvs log will disable sending diffs for
			# this commit, useful if the commit includes sensitive information
			# or if the diff will be huge
			if ($line =~ /nodiff/i) {
				$dodiffs = 0;
			}
		} else {
			if ($line =~ /^[ \t]+Tag: (.+)/) {
				$branch = $1;
			} elsif ($line =~ /^Log Message:/) {
				$startlog++;
			}
		}
	}

	# remove trailing empty lines from the log
	for (my $x = $#log; $x >= 0; $x--) {
		if (($log[$x] eq "") or ($log[$x] eq "\n")) {
			pop(@log);
		} else {
			last;
		}
	}

	# dump what we have
	foreach my $dir (keys %modfiles) {
		my @files = @{$modfiles{$dir}};
		add_formatted_files($dir, \@files, $tmp_modfiles);
	}

	foreach my $dir (keys %addfiles) {
		my @files = @{$addfiles{$dir}};
		add_formatted_files($dir, \@files, $tmp_addfiles);
	}

	foreach my $dir (keys %delfiles) {
		my @files = @{$delfiles{$dir}};
		add_formatted_files($dir, \@files, $tmp_delfiles);
	}

	if ($#diffcmds > -1) {
		open(DIFFCMDS, ">>" . $tmpdir . "/" . $tmp_diffcmd) or
			die "can't append to " . $tmpdir . "/" . $tmp_diffcmd . ": " . $!;
		print DIFFCMDS join("\n", @diffcmds) . "\n";
		close(DIFFCMDS);
	}

	if ($doimport eq "") {
		# we have more directories to look at
		if (($module . ($curdir eq "." ? "" : "/" . $curdir)) ne $lastdir) {
			exit;
		}
	}
}

# start building header
my ($login, $gecos, $fullname, $email);

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

if ($donewdir ne "") {
	push @message, "Created directory " . $donewdir . "\n";
} else {
	# add file groups
	if (-f $tmpdir . "/" . $tmp_modfiles) {
		push @message, "Modified files:\n";

		open(MODFILES, "<" . $tmpdir . "/" . $tmp_modfiles) or
			die "can't read from " . $tmpdir . "/" . $tmp_modfiles . ": " . $!;
		while (my $line = <MODFILES>) {
			push @message, $line;
		}
		close(MODFILES);
	}
	if (-f $tmpdir . "/" . $tmp_addfiles) {
		push @message, "Added files:\n";

		open(ADDFILES, "<" . $tmpdir . "/" . $tmp_addfiles) or
			die "can't read from " . $tmpdir . "/" . $tmp_addfiles . ": " . $!;
		while (my $line = <ADDFILES>) {
			push @message, $line;
		}
		close(ADDFILES);
	}
	if (-f $tmpdir . "/" . $tmp_delfiles) {
		push @message, "Removed files:\n";

		open(DELFILES, "<" . $tmpdir . "/" . $tmp_delfiles) or
			die "can't read from " . $tmpdir . "/" . $tmp_delfiles . ": " . $!;
		while (my $line = <DELFILES>) {
			push @message, $line;
		}
		close(DELFILES);
	}

	if ($doimport eq "") {
		push @message, "\n";
	}

	# add the log
	push @message, "Log message:\n";
	foreach my $line (@log) {
		push @message, "    " . $line;
	}
}

# if we're saving to a changelog, do it now before we add the diffs
if ($changelog) {
	open(CHANGELOG, ">>" . $changelog) or
		warn "can't write to " . $changelog . ": " . $!;
	foreach my $line (@message) {
		print CHANGELOG $line;
	}
	print CHANGELOG "\n";
	close(CHANGELOG);
}

if (($donewdir eq "") and ($dodiffs) and (-f $tmpdir . "/" . $tmp_diffcmd)) {
	# generate diffs
	@diffcmds = ();
	open(DIFFCMDS, "<" . $tmpdir . "/" . $tmp_diffcmd) or
		die "can't read " . $tmpdir . "/" . $tmp_diffcmd . ": " . $!;
	while (chop(my $line = <DIFFCMDS>)) {
		push @diffcmds, "cvs -nQq rdiff -u " . $line;
	}
	close(DIFFCMDS);

	if ($#diffcmds > -1) {
		push @message, "\n";
		push @message, "Diffs:\n";

		foreach my $diffcmd (@diffcmds) {
			my @args = split(" ", $diffcmd, 7);
			open(DIFF, "-|") || exec @args;
			while (my $line = <DIFF>) {
				push @message, $line;
			}
			close(DIFF);
		}
	}
}

if ($doemail) {
	# send email
	open(SENDMAIL, "| /usr/sbin/sendmail -t") or
		die "can't run sendmail: " . $!;
	print SENDMAIL "From: " . $fullname . " <" . $email . ">\n";
	print SENDMAIL "Reply-To: " . $email . "\n";
	print SENDMAIL "To: " . $doemail . "\n";
	print SENDMAIL "Subject: CVS: " . $hostname . ": " . $module . "\n";
	print SENDMAIL "\n";
	foreach my $line (@message) {
		print SENDMAIL $line;
	}
	close(SENDMAIL);
}

# clean up
unlink($tmpdir . "/" . $tmp_lastdir);
unlink($tmpdir . "/" . $tmp_modfiles);
unlink($tmpdir . "/" . $tmp_addfiles);
unlink($tmpdir . "/" . $tmp_delfiles);
unlink($tmpdir . "/" . $tmp_diffcmd);

exit;

sub add_formatted_files {
	my $dir = $_[0];
	my $files = $_[1];
	my $tmpfile = $_[2];

	if (@$files) {
		open(FILES, ">>" . $tmpdir . "/" . $tmpfile) or
			die "can't append to " . $tmpdir . "/" . $tmpfile . ": " . $!;

		print FILES "    " . $dir . (" " x (15 - length($dir))) . " :";

		# TODO: wrap files and indent
		foreach my $file (@$files) {
			print FILES " " . $file;
		}

		print FILES "\n";

		close(FILES);
	}
}
