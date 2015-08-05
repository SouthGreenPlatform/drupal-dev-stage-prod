#!/usr/bin/env perl

=pod

=head1 NAME

drupal_d2s.pl - Drupal Dev-to-Staging script

=head1 SYNOPSIS

    drupal_d2s.pl -config mgis

=head1 REQUIRES

Perl5, rsync, ssh, drush (>=7), Search-Replace-DB (with PostgreSQL support)
-both the dev and staging versions of Drupal must be running correctly (in
 order to have drush working properly)
-drush aliases must be correctly setup on both dev and staging servers
-the config file drupal_d2s.pm should be properly setup.
-for postgreSQL databases, stage server must be configured to let the dev
 server connect to its databases (pg_hba.conf)
-for postgreSQL databases, the user running drupal_d2s.pl must have its file
 ~/.pgpass setup properly in order to connect to the stage server from the dev
 server without having to enter a password.
-elasticsearch

=head1 DESCRIPTION

...+TODO


=cut

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";

use Carp qw (cluck confess croak);

use Getopt::Long;
use Pod::Usage;

use File::Path qw(remove_tree);
use POSIX qw(strftime);

use drupal_d2s;

++$|; #no buffering




# Script global constants
##########################

=pod

=head1 CONSTANTS

B<$DEBUG>: (boolean)

When set to true, it enables debug mode.

=cut

our $DEBUG = 1;




# Script global functions
##########################

=pod

=head1 FUNCTIONS

=head2 ListConfigs

B<Description>: Print the list of available configurations.

B<ArgsCount>: 0

B<Return>: nothing

=cut

sub ListConfigs
{
    if (keys(%drupal_d2s::CONFIG))
    {
        print "Available configurations:\n";
        foreach my $config (sort keys(%drupal_d2s::CONFIG))
        {
            print "'$config': " . $drupal_d2s::CONFIG{$config}->{'dev_drush_alias'} . ' --> ' . $drupal_d2s::CONFIG{$config}->{'host'} . ': ' . $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} . "\n";
        }
    }
    else
    {
        print "No configuration available!\n";
    }
    print "\n";
}


=pod

=head2 GetConfig

B<Description>: Check parameters and returns selected configuration.

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=back

B<Return>: (string)

Config name.

=cut

sub GetConfig
{
    if (!keys(%drupal_d2s::CONFIG))
    {
        confess "ERROR: No config set in config file!\n";
    }
    
    my ($parameters) = @_;
    
    # parameters check
    if ((1 != @_) || (!$parameters) || ('HASH' ne ref($parameters)))
    {
        confess "Invalid call! Missing parameters hash!\n";
    }
    
    my $config = $parameters->{'config'};

    if (!defined($config) || ($config eq ''))
    {confess "ERROR: No configuration selected!\n";}
    
    if (!exists($drupal_d2s::CONFIG{$config}))
    {
        confess "ERROR: Configuration not found '$config'!\n";
    }
    
    return $config;
}


=pod

=head2 GetRemoteSSHCommandLine

B<Description>: Returns the command line to run SSH on the remote server.

B<ArgsCount>: 1-2

=over 4

=item $config: (string) (R)

Selected configuration.

=item $include_host_user: (boolean) (O)

If set to true, the username@host argument is added to the command line.

=back

B<Return>: (string)

The command line to run SSH on the target host. SHH commands can be appended.

=cut

sub GetRemoteSSHCommandLine
{
    my ($config, $include_host_user) = @_;
    
    my $authentication = '';
    my $ssh_port   = '';

    if (($drupal_d2s::CONFIG{$config}->{'password'}) && ($drupal_d2s::CONFIG{$config}->{'identity'}))
    {
        confess "ERROR: Invalid configuration for remote host! Only a password OR an identity file should be provided, not both!\n";
    }
    elsif ($drupal_d2s::CONFIG{$config}->{'password'})
    {
        $authentication = "-o PasswordAuthentication '$drupal_d2s::CONFIG{$config}->{'password'}'";
    }
    elsif ($drupal_d2s::CONFIG{$config}->{'identity'})
    {
        $authentication = "-i " . $drupal_d2s::CONFIG{$config}->{'identity'};
    }
    
    if ($drupal_d2s::CONFIG{$config}->{'port'})
    {
        $ssh_port = '-p ' . $drupal_d2s::CONFIG{$config}->{'port'};
    }

    my $command = $drupal_d2s::SSH_PATH . ' ';

    if ($include_host_user)
    {
        $command .= $drupal_d2s::CONFIG{$config}->{'user'} . "@" . $drupal_d2s::CONFIG{$config}->{'host'} . ' ';
    }
    $command .= " $ssh_port $authentication ";

    return $command;
}


=pod

=head2 SCPLocalToRemoteFile

B<Description>: Copies a local file to the remote server using scp.

B<ArgsCount>: 3

=over 4

=item $config: (string) (R)

Selected configuration.

=item $local_file: (string) (R)

Path to local file.

=item $remote_file: (string) (R)

Path to remote file.

=back

B<Return>: (nothing)

=cut

sub SCPLocalToRemoteFile
{
    my ($config, $local_file, $remote_file) = @_;
    
    my $authentication = '';
    my $ssh_port   = '';

    if (($drupal_d2s::CONFIG{$config}->{'password'}) && ($drupal_d2s::CONFIG{$config}->{'identity'}))
    {
        confess "ERROR: Invalid configuration for remote host! Only a password OR an identity file should be provided, not both!\n";
    }
    elsif ($drupal_d2s::CONFIG{$config}->{'password'})
    {
        $authentication = "-o PasswordAuthentication '$drupal_d2s::CONFIG{$config}->{'password'}'";
    }
    elsif ($drupal_d2s::CONFIG{$config}->{'identity'})
    {
        $authentication = "-i " . $drupal_d2s::CONFIG{$config}->{'identity'};
    }
    
    if ($drupal_d2s::CONFIG{$config}->{'port'})
    {
        $ssh_port = '-P ' . $drupal_d2s::CONFIG{$config}->{'port'};
    }

    my $command = "$drupal_d2s::SCP_PATH -B -C $ssh_port $authentication '$local_file' " . $drupal_d2s::CONFIG{$config}->{'user'} . "@" . $drupal_d2s::CONFIG{$config}->{'host'} . ":$remote_file";

    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }

    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while transfering '$local_file' onto stage server:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while transfering '$local_file' onto stage server!\n";
        }
    }
}


=pod

=head2 ParseDrupalStatus

B<Description>: Parses Drush output for Drupal status and stores result into a
hash.

B<ArgsCount>: 1

=over 4

=item $drupal_status_data: (string) (R)

Drush status output.

=back

B<Return>: (hash ref)

Drupal status hash.

=cut

sub ParseDrupalStatus
{
    my ($drupal_status_data) = @_;
    
    my $drupal_status = {};

    if (!defined($drupal_status_data))
    {
        confess "ERROR: Failed to get Drupal status!\n";
    }
    elsif ($drupal_status_data =~ m/^ *Drupal version *: *(\d+\.\d+)/m)
    {
        # save parsed version
        $drupal_status->{'version'}     = $1;

        # concatenate split lines by removing EOL and spaces
        $drupal_status_data =~ s/\s+[\n\r]\s{4,}//g;
        
        ($drupal_status->{'site_uri'})       = ($drupal_status_data =~ m/^ *Site URI *: *(\S+) *$/m);
        ($drupal_status->{'db_driver'})      = ($drupal_status_data =~ m/^ *Database driver *: *(\w+)/m);
        ($drupal_status->{'db_hostname'})    = ($drupal_status_data =~ m/^ *Database hostname *: *(\w+)/m);
        ($drupal_status->{'db_username'})    = ($drupal_status_data =~ m/^ *Database username *: *(\w+)/m);
        ($drupal_status->{'db_name'})        = ($drupal_status_data =~ m/^ *Database name *: *(\w+)/m);
        ($drupal_status->{'db_status'})      = ($drupal_status_data =~ m/^ *Database *: *(\w+)/m);
        ($drupal_status->{'bootstrap'})      = ($drupal_status_data =~ m/^ *Drupal bootstrap *: *(\w+)/m);
        ($drupal_status->{'drupal_user'})    = ($drupal_status_data =~ m/^ *Drupal user *: *([^\n\r]+?) *$/m);
        ($drupal_status->{'drupal_theme'})   = ($drupal_status_data =~ m/^ *Default theme *: *([^\n\r]+?) *$/m);
        ($drupal_status->{'drupal_root'})    = ($drupal_status_data =~ m/^ *Drupal root *: *(\S+?) *$/m);
        ($drupal_status->{'site_path'})      = ($drupal_status_data =~ m/^ *Site path *: *(\S+?) *$/m);
        ($drupal_status->{'site_file_path'}) = ($drupal_status_data =~ m/^ *File directory path *: *(\S+?) *$/m);
        ($drupal_status->{'site_private_file_path'}) = ($drupal_status_data =~ m/^ *Private file directory path *: *(\S+?) *$/m);
    }
    else
    {
        confess "ERROR: Failed to parse Drupal status!\n";
    }
    
    if ($DEBUG)
    {
        warn "Drush output:\n----------\n" . $drupal_status_data . "\n----------\n";
        warn "Data parsed:\n----------\n";
        while (my ($key, $value) = each(%$drupal_status))
        {
            warn "  $key => $value\n";
        }
        warn "----------\n";
    }
    
    return $drupal_status;
}


=pod

=head2 GetDevCoreStatus

B<Description>: Return developpment Drupal informations.

B<Return>: (hash ref)

Developpment informations.

=cut

sub GetDevCoreStatus
{
    my ($parameters) = @_;
    
    my $config = GetConfig($parameters);

    my $command = "$drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'dev_drush_alias'} status";
    my $core_version_data = `$command 2>&1`;
    my $stage_status = ParseDrupalStatus($core_version_data);
    
    if (%$stage_status)
    {
        $command = "$drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'dev_drush_alias'} ev 'global \$databases; echo \$databases[\"default\"][\"default\"][\"password\"];'";
        if ($DEBUG)
        {
            print "COMMAND:\n$command\n"; #+debug
        }
        my $db_password = `$command`;
        if ($db_password)
        {
            $stage_status->{'db_password'} = $db_password;
        }
    }

    return $stage_status;
}


=pod

=head2 GetStageCoreStatus

B<Description>: Return staging site informations.

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=back

B<Return>: (hash ref)

Stage informations.

=cut

sub GetStageCoreStatus
{
    my ($parameters) = @_;
    
    my $config = GetConfig($parameters);

    # get drush status (through ssh)
    my $command = GetRemoteSSHCommandLine($config, 1);
    $command .= " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} status";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $core_version_data = `$command 2>&1`;

    my $stage_status = ParseDrupalStatus($core_version_data);
    
    if (%$stage_status)
    {
        $command = GetRemoteSSHCommandLine($config, 1);
        my $php_command = 'global \\$databases; echo \\$databases[\\"default\\"][\\"default\\"][\\"password\\"];';
        $command .= " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} ev \"'$php_command'\"";
        if ($DEBUG)
        {
            print "COMMAND:\n$command\n"; #+debug
        }
        my $db_password = `$command`;
        if ($db_password)
        {
            $stage_status->{'db_password'} = $db_password;
        }
    }

    return $stage_status;
}


=pod

=head2 SetDevSiteOffline

B<Description>: Set dev site offline (or online according to the parameters).

B<ArgsCount>: 1-2

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=item $offline_status: (boolean) (O)

Offline status. Can be 0 or 1. Default: 1 (=set offline).

=back

B<Return>: nothing

=cut

sub SetDevSiteOffline
{
    my ($parameters, $offline_status) = @_;

    my $config = GetConfig($parameters);

    if (!defined($offline_status) || ($offline_status !~ m/^[01]$/))
    {
        # offline by default
        $offline_status = 1;
    }

    # set drush online status
    my $command = "$drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'dev_drush_alias'} vset --always-set maintenance_mode $offline_status --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while setting dev site offline:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while setting dev site offline!\n";
        }
    }
}


=pod

=head2 SetStageSiteOffline

B<Description>: Set staging site offline (or online according to the parameters).

B<ArgsCount>: 1-2

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=item $offline_status: (boolean) (O)

Offline status. Can be 0 or 1. Default: 1 (=set offline).

=back

B<Return>: nothing

=cut

sub SetStageSiteOffline
{
    my ($parameters, $offline_status) = @_;
    
    my $config = GetConfig($parameters);
    
    if (!defined($offline_status) || ($offline_status !~ m/^[01]$/))
    {
        # offline by default
        $offline_status = 1;
    }

    # set drush online status (through ssh)
    my $command = GetRemoteSSHCommandLine($config, 1);
    $command .= " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} vset --always-set site_offline $offline_status --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while setting stage site offline:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while setting stage site offline!\n";
        }
    }
}


=pod

=head2 ClearDevSiteCache

B<Description>: Clear dev site cache.

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=back

B<Return>: nothing

=cut

sub ClearDevSiteCache
{
    my ($parameters) = @_;

    my $config = GetConfig($parameters);

    # set drush online status
    my $command = "$drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'dev_drush_alias'} cache-clear all";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while clearing dev site cache:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while clearing dev site cache!\n";
        }
    }
}


=pod

=head2 DumpDevSite

B<Description>: Dumps dev site database and return the dump file name.

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=back

B<Return>: (string)

Dump file path.

=cut

sub DumpDevSite
{
    my ($parameters) = @_;

    my $config = GetConfig($parameters);

    my $sql_dump_file = "$drupal_d2s::TEMP_PATH/" . $config . "_d2s.sql";
    
    if (-e $sql_dump_file)
    {
        # remove previous dump
        if (!unlink($sql_dump_file))
        {
            confess "ERROR: Failed to remove previous database dump '$sql_dump_file'!\nerrno: $!\n";
        }
    }
    
    # use drush to dump database
    my $command = "$drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'dev_drush_alias'} sql-dump --result-file='$sql_dump_file' --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while dumping dev site database:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while dumping dev site database!\n";
        }
    }

    if (!-e $sql_dump_file)
    {
        confess "ERROR: Failed to generate database dump '$sql_dump_file'!\n";
    }

    return $sql_dump_file;
}


=pod

=head2 LoadDumpOnStageSite

B<Description>: .

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=item $stage_status: (hash ref) (R)

Hash of drupal stage status.

=item $sql_dump_file: (string) (R)

Path of the SQL dump file to load into database.

=back

B<Return>: nothing

=cut

sub LoadDumpOnStageSite
{
    my ($parameters, $stage_status, $sql_dump_file) = @_;

    my $config = GetConfig($parameters);
    
    # transfer dump file to remote host
    SCPLocalToRemoteFile($config, $sql_dump_file, $sql_dump_file);

    # use drush to load database dump (through ssh)
    my $command = GetRemoteSSHCommandLine($config, 1);
    $command .= " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} sql-cli --yes --extra=";
    if ($stage_status->{'db_driver'} =~ m/pg?sql/i)
    {
        $command .= "'--file=\"$sql_dump_file\"'";
    }
    else
    {
        $command .= "'-e \"\\. $sql_dump_file\"'";
    }


    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }

    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while loading database dump onto stage:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while loading database dump onto stage!\n";
        }
    }
    
    # remove remote file
    $command = GetRemoteSSHCommandLine($config, 1);
    $command .= " rm -f '$sql_dump_file'";
    $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while loading database dump onto stage:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while loading database dump onto stage!\n";
        }
    }

}


=pod

=head2 ReplaceDBStrings

B<Description>: Replace strings into stage database as specified in the
configuration.

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=item $stage_status: (hash ref) (R)

Hash of drupal stage status.

=back

B<Return>: nothing

=cut

sub ReplaceDBStrings
{
    my ($parameters, $stage_status) = @_;

    my $config = GetConfig($parameters);

    # replace command
    my $command = "php -f $drupal_d2s::SEARCH_REPLACE_DB_PATH -- ";

    if ($stage_status->{'db_driver'} =~ m/pg?sql/i)
    {
        $command .= "-d pgsql ";
    }
    else
    {
        $command .= "-d mysql ";
    }
    my $db_host = $stage_status->{'db_hostname'};
    if (!$db_host || ($db_host =~ m/localhost|127.0.0.1/))
    {
        $db_host = $drupal_d2s::CONFIG{$config}->{'host'};
    }
    $command .= "-h $db_host -n $stage_status->{'db_name'} -u $stage_status->{'db_username'} -p '$stage_status->{'db_password'}'";

    while (my ($search_string, $replace_string) = each %{$drupal_d2s::CONFIG{$config}->{'replacements'}})
    {
        my $replace_command = "$command -s '$search_string' -r '$replace_string' ";
        if ($DEBUG)
        {
            warn "DEBUG: COMMAND:\n$replace_command\n"; #+debug
        }

        my $exist_status = system($replace_command);
        if ($exist_status)
        {
            if (-1 == $exist_status)
            {
                confess "ERROR: An error occurred while replacing stage database strings:\n$!\n";
            }
            else
            {
                confess "ERROR: An error occurred while replacing stage database strings!\n";
            }
        }
    }

}


=pod

=head2 UpdateStageDatabase

B<Description>: .

B<Return>: nothing

=cut

sub UpdateStageDatabase
{
    my ($parameters) = @_;
    
    my $config = GetConfig($parameters);
    
    # run updatedb
    my $command = GetRemoteSSHCommandLine($config, 1);
    $command .= " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} updatedb --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while updating stage database:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while updating stage database!\n";
        }
    }
}


=pod

=head2 RunDevToStageRSync

B<Description>: .

B<Return>: nothing

=cut

sub RunDevToStageRSyncForDirectory
{
    my ($parameters, $dev_path, $stage_path) = @_;
    
    my $config = GetConfig($parameters);
    
    if (!$dev_path || !$stage_path || ($dev_path !~ m/\w+/) || ($stage_path !~ m/\w+/))
    {
        confess "ERROR: invalid RunDevToStageRSyncForDirectory call: missing a path argument!\n";
    }

    my $target_path = $drupal_d2s::CONFIG{$config}->{'user'} . '@' . $drupal_d2s::CONFIG{$config}->{'host'} . ':' . $stage_path;

    # run rsync
    my $ssh_command = GetRemoteSSHCommandLine($config, 0);
    my @rsync_args = (
        "--verbose",
        "--checksum",
        "--recursive",
        "--copy-unsafe-links",
#        "--times",
        "--exclude=.git",
        "--exclude=.svn",
#        "--perms",
        "--delete-after",
        "--force",
        "--compress",
        "--skip-compress=zip,gz,tgz,tbz,bzip,bz2,jpg,jpeg,png,ogg,mp[34],mpeg,avi,mov,swf,mkv,rpm,deb",
        "--rsh=$ssh_command",
        "$dev_path/",
        "$target_path",
    );
    
    my $command = $drupal_d2s::RSYNC_PATH . ' ' . join(' ', @rsync_args);
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }

    my $exist_status = system {$drupal_d2s::RSYNC_PATH} $drupal_d2s::RSYNC_PATH, @rsync_args;
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while running rsync:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while running rsync!\n";
        }
    }
}


=pod

=head2 PrepareStageFileAccess

B<Description>: .

B<Return>: nothing

=cut

sub PrepareStageFileAccess
{
    my ($parameters, $stage_status) = @_;
    
    my $config = GetConfig($parameters);
    
    # 
    my $command = GetRemoteSSHCommandLine($config, 1);
    $command .= " $drupal_d2s::CONFIG{$config}->{'set_user_access'} $drupal_d2s::CONFIG{$config}->{'user'}";

    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while preparing stage file access rights:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while preparing stage file access rights!\n";
        }
    }
}


=pod

=head2 AdjustStageFileAccess

B<Description>: .

B<Return>: nothing

=cut

sub AdjustStageFileAccess
{
    my ($parameters, $stage_status) = @_;
    
    my $config = GetConfig($parameters);

    # 
    my $command = GetRemoteSSHCommandLine($config, 1);
    $command .= " $drupal_d2s::CONFIG{$config}->{'set_web_access'}";

    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while preparing stage file access rights:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while preparing stage file access rights!\n";
        }
    }
}


=pod

=head2 BackupDevElasticSearchIndices

B<Description>: .

B<Return>: (string)

=cut

sub BackupDevElasticSearchIndices
{
    my ($parameters, $dev_status) = @_;
    
    my $config = GetConfig($parameters);

    my $snapshot_name = 'snapshot_' . strftime('%Y%m%d', localtime) . '_' . $$;
    
    my $index_names = join(',', map
        {
            return $drupal_d2s::ES_INDEX_PREFIX . $dev_status->{'db_name'} . $_;
        }
        @{$drupal_d2s::CONFIG{$config}->{'es_index_suffixes'}}
    );

    # remove any previous snapshot
    my $command = qq|/usr/bin/curl -XDELETE "localhost:9200/_snapshot/mgis_accession_backup/$snapshot_name"|;
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }

    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            warn "ERROR: An error occurred while removing previous ES indices snapshot ($snapshot_name):\n$!\n";
        }
        else
        {
            warn "ERROR: An error occurred while removing previous ES indices snapshot ($snapshot_name)!\n";
        }
    }

    # backup current indices
    $command = qq|/usr/bin/curl -XPUT 'localhost:9200/_snapshot/mgis_accession_backup/$snapshot_name' -d '{
        "indices": "$index_names",
        "ignore_unavailable": true,
        "include_global_state": false
    }'|;

    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    
    $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while creating ES indices snapshot ($snapshot_name):\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while creating ES indices snapshot ($snapshot_name)!\n";
        }
    }
    
    return $snapshot_name;
}


=pod

=head2 TransferElasticSearchIndices

B<Description>: .

B<Return>: nothing

=cut

sub TransferElasticSearchIndices
{
    my ($parameters, $dev_status, $stage_status, $snapshot_name) = @_;
    
    my $config = GetConfig($parameters);

    foreach my $index_suffix (@{$drupal_d2s::CONFIG{$config}->{'es_index_suffixes'}})
    {
        my $dev_index_name = $drupal_d2s::ES_INDEX_PREFIX . $dev_status->{'db_name'} . $index_suffix;
        my $stage_index_name = $drupal_d2s::ES_INDEX_PREFIX . $stage_status->{'db_name'} . $index_suffix;
        
        # close stage index
        my $command = qq|/usr/bin/curl -XPOST 'localhost:9200/$stage_index_name/_close'|;
        if ($DEBUG)
        {
            warn "DEBUG: COMMAND:\n$command\n"; #+debug
        }
        
        my $exist_status = system($command);
        if ($exist_status)
        {
            if (-1 == $exist_status)
            {
                warn "ERROR: An error occurred while closing index '$stage_index_name':\n$!\n";
            }
            else
            {
                warn "ERROR: An error occurred while closing index '$stage_index_name'!\n";
            }
        }

        # restore dev index into stage index
        $command = qq|/usr/bin/curl -XPOST "localhost:9200/_snapshot/mgis_accession_backup/$snapshot_name/_restore" -d '{
            "indices": "$dev_index_name",
            "ignore_unavailable": true,
            "include_global_state": false,
            "rename_pattern": "$dev_index_name",
            "rename_replacement": "$stage_index_name"
        }'|;

        if ($DEBUG)
        {
            warn "DEBUG: COMMAND:\n$command\n"; #+debug
        }

        $exist_status = system($command);
        if ($exist_status)
        {
            if (-1 == $exist_status)
            {
                confess "ERROR: An error occurred while reloading index '$stage_index_name':\n$!\n";
            }
            else
            {
                confess "ERROR: An error occurred while reloading index '$stage_index_name'!\n";
            }
        }
    }

}




=pod

=head2 UnsetStageThemeRegistryRebuild

B<Description>: .

B<Return>: nothing

=cut

sub UnsetStageThemeRegistryRebuild
{
    my ($parameters, $stage_status) = @_;
    
    my $config = GetConfig($parameters);

    # remove theme registry rebuild
    my $sql_qery = q|UPDATE variable SET value = replace(value::varchar, 's:20:"zen_rebuild_registry";i:1;', 's:20:"zen_rebuild_registry";i:0;')::bytea WHERE value LIKE '%s:20:"zen_rebuild_registry";i:1;%';|;

    my $command = GetRemoteSSHCommandLine($config, 1);
    #$command .= " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} vset --always-set site_offline $offline_status --yes";
    $command .= " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} sql-query \"$sql_qery\"  --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while disabling theme registry rebuild:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while disabling theme registry rebuild!\n";
        }
    }

}


=pod

=head2 EnableStageCache

B<Description>: .

B<Return>: nothing

=cut

sub EnableStageCache
{
    my ($parameters, $stage_status) = @_;
    
    my $config = GetConfig($parameters);

    my $command_prefix = GetRemoteSSHCommandLine($config, 1);

    # Cache
    my $command = $command_prefix . " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} vset --always-set cache 1 --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            warn "ERROR: An error occurred while enabling cache:\n$!\n";
        }
        else
        {
            warn "ERROR: An error occurred while enabling cache!\n";
        }
    }
    # also maybe "block_cache 1" and "page_compression 1"

    # CSS
    $command = $command_prefix . " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} vset --always-set preprocess_css 1 --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            warn "ERROR: An error occurred while enabling css preprocessing:\n$!\n";
        }
        else
        {
            warn "ERROR: An error occurred while enabling css preprocessing!\n";
        }
    }

    # JS
    $command = $command_prefix . " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} vset --always-set preprocess_js 1 --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            warn "ERROR: An error occurred while enabling js preprocessing:\n$!\n";
        }
        else
        {
            warn "ERROR: An error occurred while enabling js preprocessing!\n";
        }
    }

}


=pod

=head2 EnableOtherStageOptimizations

B<Description>: .

B<Return>: nothing

=cut

sub EnableOtherStageOptimizations
{
    my ($parameters, $stage_status) = @_;
    
    my $config = GetConfig($parameters);

    my $command_prefix = GetRemoteSSHCommandLine($config, 1);

    # remove messages
    my $command = $command_prefix . " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} vset --always-set error_level 0 --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while enabling cache:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while enabling cache!\n";
        }
    }

    # disable some modules
    if ($drupal_d2s::CONFIG{$config}->{'disable_modules'}
        && @{$drupal_d2s::CONFIG{$config}->{'disable_modules'}})
    {
        $command = $command_prefix . " $drupal_d2s::DRUSH_PATH $drupal_d2s::CONFIG{$config}->{'stage_drush_alias'} dis " . join(' ', @{$drupal_d2s::CONFIG{$config}->{'disable_modules'}}) . " -y";
        if ($DEBUG)
        {
            warn "DEBUG: COMMAND:\n$command\n"; #+debug
        }
        $exist_status = system($command);
        if ($exist_status)
        {
            if (-1 == $exist_status)
            {
                warn "ERROR: An error occurred while disabling some modules:\n$!\n";
            }
            else
            {
                warn "ERROR: An error occurred while disabling some modules!\n";
            }
        }
    }

}


=pod

=head2 SetOptimizations

B<Description>: .

B<Return>: nothing

=cut

sub SetOptimizations
{
    my ($parameters, $stage_status) = @_;
    eval
    {
        # UnsetStageThemeRegistryRebuild($parameters, $stage_status);
    };
    
    if ($@)
    {
        warn $@;
    }
   
    eval
    {
        EnableStageCache($parameters, $stage_status);
    };

    if ($@)
    {
        warn $@;
    }
   
    eval
    {
        EnableOtherStageOptimizations($parameters, $stage_status);
    };

    if ($@)
    {
        warn $@;
    }
   
}




# Script options
#################

=pod

=head1 OPTIONS

    drupal_d2s.pl [-help | -man]

    drupal_d2s.pl [-dev <PATH>] [-config <CONFIG>]

=head2 Parameters

=over 4

=item B<-help>:

Prints a brief help message and exits.

=item B<-man>:

Prints the manual page and exits.

=item B<-debug>:

Executes the script in debug mode.

=item B<-list> (flag)

List available configurations.

=item B<-config> (string)

Configuration name to use.

=item B<-init> (flag)

Initialize remote repository.

=item B<-local-init> (flag)

Initialize local directory as a drupal_d2s directory.

=item B<-push> (flag)

Update remote repository.

=item B<-pull> (flag)

Create or update local copy.

=item B<-force> (flag)

Force update even if versions mismatch.

=item B<-auto-update> (integer)

Delay in minutes between auto-updates (for push and pull only). When set, the
script will keep updating (either push or pull) every amount of minutes. It can
be killed and should only be killed while waiting before the next update.
Before restarting next update, a 1 minute count down is displayed.

=item B<-directory> (string)

Use specified directory instead of the configuration one as local copy path.

=back

=cut


# CODE START
#############

# options processing
my ($man, $help, $debug) = (0, 0, 0);
my ($config, $list_configs, $transfer_database, $transfer_indices);

print "$drupal_d2s::D2S_VERSION\n\n";

# parse options and print usage if there is a syntax error.
GetOptions('help|?'     => \$help,
           'man'        => \$man,
           'debug'      => \$debug,
           'c|config=s' => \$config,
           'list'       => \$list_configs,
           'd|db|database' => \$transfer_database,
           'i|indices|index' => \$transfer_indices,
) or pod2usage(1);
if ($help) {pod2usage('-verbose' => 1, '-exitval' => 0);}
if ($man) {pod2usage('-verbose' => 2, '-exitval' => 0);}

# change debug mode if requested/forced
$DEBUG ||= $debug;

# only list available configs?
if ($list_configs)
{
    ListConfigs();
    exit(0);
}

my $parameters = {
    'config' => $config,
};

if ($DEBUG)
{
    warn "Using config '$config'\n"; #+debug
}

if ($DEBUG)
{
    warn "Getting dev site status\n"; #+debug
}
my $dev_status   = GetDevCoreStatus($parameters);

if ($DEBUG)
{
    warn "Getting stage site status\n"; #+debug
}
my $stage_status = GetStageCoreStatus($parameters);

if ($DEBUG)
{
    warn "Dev:   " . $dev_status->{'version'} . "\n"; #+debug
    warn "Stage: " . $stage_status->{'version'} . "\n"; #+debug
}

# check stage core version versus dev core version and stops if different
if ($dev_status->{'version'} != $stage_status->{'version'})
{
    confess "ERROR: Drupal core version differs between developpment site and staging site! Please update Drupal core on the staging site first.\n";
}

# check for DB transfer
my $sql_dump_file;
if ($transfer_database)
{
    if ($DEBUG)
    {
        warn "Dumping dev database...\n"; #+debug
    }

    # put dev site offline
    SetDevSiteOffline($parameters, 1);
    # remove cache
    ClearDevSiteCache($parameters);
    # dump dev database
    $sql_dump_file = DumpDevSite($parameters);
    # put dev site back online
    SetDevSiteOffline($parameters, 0);
}

# put staging site offline
SetStageSiteOffline($parameters, 1);

if ($DEBUG)
{
    warn "Prepare access rights...\n"; #+debug
}
# prepare access rights
PrepareStageFileAccess($parameters, $stage_status);

if ($DEBUG)
{
    warn "RSync files...\n"; #+debug
}
# launch rsync on files directory (with access rights)
RunDevToStageRSyncForDirectory(
    $parameters,
    "$dev_status->{'drupal_root'}/$dev_status->{'site_file_path'}",
    "$stage_status->{'drupal_root'}/$stage_status->{'site_file_path'}",
);

# launch rsync on private files directory (with access rights)
if ($dev_status->{'site_private_file_path'})
{
    if (!$stage_status->{'site_private_file_path'})
    {
        warn "WARNING: Missing staging private file path! No sync made on private files!\n";
    }
    else
    {
        RunDevToStageRSyncForDirectory(
            $parameters,
            "$dev_status->{'site_private_file_path'}",
            "$stage_status->{'site_private_file_path'}",
        );
    }
}

# launch rsync on libraries
RunDevToStageRSyncForDirectory(
    $parameters,
    "$dev_status->{'drupal_root'}/$dev_status->{'site_path'}/libraries",
    "$stage_status->{'drupal_root'}/$stage_status->{'site_path'}/libraries",
);

# launch rsync on themes
RunDevToStageRSyncForDirectory(
    $parameters,
    "$dev_status->{'drupal_root'}/$dev_status->{'site_path'}/themes",
    "$stage_status->{'drupal_root'}/$stage_status->{'site_path'}/themes",
);

# launch rsync on modules
RunDevToStageRSyncForDirectory(
    $parameters,
    "$dev_status->{'drupal_root'}/$dev_status->{'site_path'}/modules",
    "$stage_status->{'drupal_root'}/$stage_status->{'site_path'}/modules",
);

if ($DEBUG)
{
    warn "Adjust access rights...\n"; #+debug
}
# adjust access rights
AdjustStageFileAccess($parameters, $stage_status);

# check for DB transfer
if ($transfer_database)
{
    if ($DEBUG)
    {
        warn "Reload staging database and update strings...\n"; #+debug
    }
    # load dump on stage
    LoadDumpOnStageSite($parameters, $stage_status, $sql_dump_file);
    # remove dump after use
    # unlink($sql_dump_file);

    # run DB replacements
    ReplaceDBStrings($parameters, $stage_status);
}

# run updatedb on stage
UpdateStageDatabase($parameters);

# transfer elastic search indices if requested
if ($transfer_indices
    && $drupal_d2s::CONFIG{$config}->{'es_index_suffixes'}
    && @{$drupal_d2s::CONFIG{$config}->{'es_index_suffixes'}})
{
    if ($DEBUG)
    {
        warn "Transfering elasticsearch indices...\n"; #+debug
    }

    # backup dev indices
    my $snapshot_name = BackupDevElasticSearchIndices($parameters, $dev_status);
    
    # reload on stage
    TransferElasticSearchIndices($parameters, $dev_status, $stage_status, $snapshot_name);
}

# set optimizations
SetOptimizations($parameters, $stage_status);

# put back stage online
SetStageSiteOffline($parameters, 0);


exit(0);

__END__
# CODE END
###########

=pod

=head1 AUTHORS

Valentin GUIGNON (Bioversity), v.guignon@cgiar.org

=head1 VERSION

Version 1.2.0

Date 18/11/2014

=cut
