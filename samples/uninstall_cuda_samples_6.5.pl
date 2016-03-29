#!/usr/bin/perl

use strict;

use File::Basename qw(dirname);
use Getopt::Long;

my $manifest;
my $silent = 0;

my $retval = GetOptions(
    "manifest=s" => \$manifest,
    "silent" => \$silent,
    "help" => sub { Usage() },
);

if (!$manifest)
{
    $manifest = dirname(__FILE__) . "/.uninstall_manifest_do_not_delete.txt";
}

if (! -f $manifest)
{
    print "Uninstall manifest file not found.\n";
    Usage(1);
}

my @uninstallation_dirs;
my %uninstallation_links;
my %uninstallation_files;

ParseManifest();

ValidateWritable();

PerformUninstall();

sub ParseManifest
{
    open MANIFEST, '<', $manifest;
    while (<MANIFEST>)
    {
        chomp $_;

        next if ($_ =~ m|^\s*#|);

        my @line_data = split(':', $_);
        my $data_type = $line_data[0];

        if ($data_type eq "file")
        {
            $uninstallation_files{$line_data[1]} = $line_data[2];
        }
        elsif ($data_type eq "dir")
        {
            push (@uninstallation_dirs, $line_data[1]);
        }
        elsif ($data_type eq "link")
        {
            $uninstallation_links{$line_data[1]} = $line_data[2];
        }
    }
    close MANIFEST;
}

sub ValidateWritable
{
    for my $file (keys(%uninstallation_files))
    {
        if (-f $file && ! -w $file)
        {
            Unwritable($file);
        }
    }

    for my $link (keys(%uninstallation_links))
    {
        if (-l $link && ! -w $link)
        {
            Unwritable($link);
        }
    }

    for my $dir (@uninstallation_dirs)
    {
        if (-d $dir && ! -w $dir)
        {
            Unwritable($dir);
        }
    }
}

sub Unwritable
{
    my $file = shift;

    if (!$file)
    {
        $file = "the files";
    }
    
    print <<END;
Unable to get write permissions for $file.
Ensure you have the appropriate permissions to uninstall. You may need to run
the uninstall as root or via sudo.
END
    exit(1);
}

my $MD5_Module_Detected = undef;
sub DetectMD5Module
{
    return $MD5_Module_Detected if (defined $MD5_Module_Detected);

    eval
    {
        require Digest::MD5;
        Digest::MD5->import(qw(md5_hex));
    };

    if ($@)
    {
        $MD5_Module_Detected = 0;
    }
    else
    {
        $MD5_Module_Detected = 1;
    }

    return $MD5_Module_Detected;
}

sub GetMD5
{
    my $md5;
    my $file = shift;

    if (DetectMD5Module())
    {
        open FILE, "$file";
        binmode FILE;
        my $data = <FILE>;
        close FILE;
        $md5 = md5_hex($data);
    }
    else
    {
        $md5 = `md5sum $file 2>/dev/null | awk '{print \$1}'`;
        chomp $md5;
    }

    return $md5;
}

#
# Here are the rules for an uninstall:
# 1. For each link, remove link
#    a. If link does not exist, warn user
#    b. If link is no longer a link, warn user
# 2. For each file, remove file if md5 sums match.
#    a. If md5 sums mismatch, do not remove and warn user
#    b. If file does not exist, warn user
#    c. If file is no longer a file, warn user
# 3. For each dir, remove dir in order of decreasing depth
#    a. If dir is not empty, do not remove and warn user
#    b. If dir does not exist, warn user
#    c. If dir is no longer a dir, warn user
#
sub PerformUninstall
{
    RemoveFile($manifest);

    for my $link (keys(%uninstallation_links))
    {
        if (-l $link)
        {
            if (readlink($link) eq $uninstallation_links{$link})
            {
                RemoveFile($link);
            }
            else
            {
                print "Not removing symbolic link, it appears to have been modified after installation: $link\n" if (!$silent);
            }
        }
        elsif (-e $link)
        {
            print "Not removing expected symbolic link, it exists but is no longer a symbolic link: $link\n" if (!$silent);
        }
        else
        {
            print "Expected symbolic link, but it no longer exists: $link\n" if (!$silent);
        }
    }

    for my $file (keys(%uninstallation_files))
    {
        my $md5 = GetMD5($file);

        if (! -e $file && ! -l $file)
        {
            print "Expected file, but it no longer exists: $file\n" if (!$silent);
        }
        elsif (! -f $file || -l $file)
        {
            print "Not removing expected file, it exists but is no longer a file: $file\n" if (!$silent);
        }
        elsif ($md5 ne $uninstallation_files{$file})
        {
            print "Not removing file, it appears to have been modified after installation: $file\n" if (!$silent);
        }
        else
        {
            RemoveFile($file);
        }
    }

    for my $dir (sort {$b cmp $a} uniq(@uninstallation_dirs))
    {
        opendir DIR, "$dir";
        my $empty = 1;
        while (my $file = readdir(DIR))
        {
            if ($file ne "." && $file ne "..")
            {
                $empty = 0;
                last;
            }
        }

        if ($empty)
        {
            RemoveDir($dir);
        }
        else
        {
            print "Not removing directory, it is not empty: $dir\n" if (!$silent);
        }
    }
}

sub uniq
{
    my %seen = ();
    my @ret = ();

    foreach my $element (@_)
    {
        unless ($seen{$element})
        {
            push @ret, $element;
            $seen{$element} = 1;
        }
    }

    return @ret;
}

sub RemoveDir
{
    my $dir = shift;

    if (!$dir)
    {
        return;
    }

    print "Removing directory $dir\n" if (!$silent);
    rmdir $dir;
}

sub RemoveFile
{
    my $file = shift;

    if (!$file)
    {
        return;
    }

    print "Removing $file\n" if (!$silent);
    unlink $file;
}

sub Usage
{
    my $code = 0;
    $code = shift;

    print <<END;

Usage:
    perl uninstall.pl <Options>
Options:
    --manifest=<PATH>   : optional path to uninstallation manifest. Defaults to .uninstall_manifest_do_not_delete.txt
    --silent            : don't print standard uninstallation messages (only print error messages)
END

    exit($code);
}
