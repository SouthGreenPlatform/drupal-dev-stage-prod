=pod

=head1 NAME

drupal_dsp - Drupal Dev-Staging-Prod library file

=head1 SYNOPSIS

    use drupal_dsp;
    

=head1 REQUIRES

Perl5

=head1 EXPORTS

GetSiteAliases  ShowSiteList  ParseDrupalStatus  GetCoreStatus  GetModules
SetSiteVariable  SwapSymLinks  RunRSyncForDirectory  RemoveDirectory
IsModuleAvailable  IsModuleEnabled  LockSite  UnlockSite
PrepareStageFileAccessForUpdate  AdjustStageFileAccessForWeb
DumpSite  LoadDumpOnSite  ReplaceDBStrings  UpdateDatabase

=head1 DESCRIPTION

Contains Drupal Dev-Staging-Prod helper functions.

=cut

package drupal_dsp;


use strict;
use warnings;

use Carp qw (cluck confess croak);
use JSON;

use base qw(Exporter);

our @EXPORT = qw(
    GetSiteAliases  ShowSiteList  ParseDrupalStatus  GetCoreStatus  GetModules
    IsModuleAvailable  IsModuleEnabled  LockSite  UnlockSite
    SetSiteVariable  SwapSymLinks  RunRSyncForDirectory  RemoveDirectory
    PrepareStageFileAccessForUpdate  AdjustStageFileAccessForWeb
    DumpSite  LoadDumpOnSite  ReplaceDBStrings  UpdateDatabase
);


# Package global constants
##########################

=pod

=head1 CONSTANTS

B<$DEBUG>: (boolean)

When set to true, it enables debug mode.

B<$ES_INDEX_PREFIX>:  (string)

Prefix used by elasticsearch indexes.

=cut

our $D2S_VERSION            = 'Drupal Dev-Stage-Prod v1.0';
our $ES_INDEX_PREFIX        = 'elasticsearch_index_';
our $MODULE_TYPE_MODULE     = 'Module';
our $MODULE_TYPE_THEME      = 'Theme';
our $MODULE_STATUS_ENABLED  = 'Enabled';
our $MODULE_STATUS_DISABLED = 'Disabled';
our $DRUSH_STAGE_PREFIX     = '@stage.';
our $DRUSH_PROD_PREFIX      = '@prod.';
our $DRUSH_ALL_SUFFIX       = 'all';
our $DEFAULT_CONFIG         = 'default';


# Package subs
###############

=pod

=head1 FUNCTIONS

=head2 GetSiteAliases

B<Description>: Return the list of available sites in a hash.

B<ArgsCount>: 0

B<Return>: (hash ref)

A hash with site aliases as keys and array of available versions for each site as
values. Site versions can be 'dev', 'stage' and 'prod'.

=cut

sub GetSiteAliases
{
    my ($group_filter, $access_config) = @_;

    my $command = "$drupal_p2s::DRUSH_PATH site-alias --fields=#name --format=csv";
    if ($access_config)
    {
        # get drush status (through ssh)
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
    }
    if ($DEBUG)
    {
        print "COMMAND:\n$command\n"; #+debug
    }
    my $site_raw_aliases = `$command 2>&1`;
    if ($?)
    {
        confess "ERROR: an error occurred while executing:\n$command\n\n$site_raw_aliases\n";
    }

    # associative hash stage_site => prod_site
    my %site_aliases;
    if ($site_raw_aliases)
    {
        if (!defined($group_filter))
        {
            $group_filter = 'dev|stage|prod';
        }

        foreach my $site_alias (split(/[\s\r\n]+/, $site_raw_aliases))
        {
            if ($site_alias =~ m/^($group_filter)\.(\w+)$/)
            {
                if ($2 ne 'all')
                {
                    $site_aliases{$2} ||= [];
                    push(@{$site_aliases{$2}}, $1);
                }
            }
        }
    }
    else
    {
        confess "ERROR: Failed to get list of sites!\n";
    }

    if ($DEBUG)
    {
        print "DEBUG: Got aliases: " . join(', ', keys(%site_aliases)) . "\n"; #+debug
    }

    return \%site_aliases;
}



=pod

=head2 ShowSiteList

B<Description>: Print the list of available site configurations.

B<ArgsCount>: 1

=over 4

=item $site_aliases: (array) (R)

Array of site aliases (strings).

=back

B<Return>: nothing

=cut

sub ShowSiteList
{
    my ($site_aliases) = @_;
    print "-----------------+-------------\nSite alias:      | Setup for:\n-----------------+-------------\n";
    foreach my $alias (sort keys(%$site_aliases))
    {
        printf("% -16s | %s\n",  $alias, join(', ', sort @{$site_aliases->{$alias}}));
    }
    print "-----------------+-------------\n";
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
        
        ($drupal_status->{'site_uri'})       = ($drupal_status_data =~ m/^ *Site URI *: *(\S+) *$/mi);
        ($drupal_status->{'db_driver'})      = ($drupal_status_data =~ m/^ *Database driver *: *(\w+)/mi);
        ($drupal_status->{'db_hostname'})    = ($drupal_status_data =~ m/^ *Database hostname *: *(\w+)/mi);
        ($drupal_status->{'db_username'})    = ($drupal_status_data =~ m/^ *Database username *: *(\w+)/mi);
        ($drupal_status->{'db_password'})    = ($drupal_status_data =~ m/^ *Database password *: *([^\n\r]+)/mi);
        ($drupal_status->{'db_name'})        = ($drupal_status_data =~ m/^ *Database name *: *(\w+)/mi);
        ($drupal_status->{'db_status'})      = ($drupal_status_data =~ m/^ *Database *: *(\w+)/mi);
        ($drupal_status->{'bootstrap'})      = ($drupal_status_data =~ m/^ *Drupal bootstrap *: *(\w+)/mi);
        ($drupal_status->{'drupal_user'})    = ($drupal_status_data =~ m/^ *Drupal user *: *([^\n\r]+?) *$/mi);
        ($drupal_status->{'drupal_theme'})   = ($drupal_status_data =~ m/^ *Default theme *: *([^\n\r]+?) *$/mi);
        ($drupal_status->{'drupal_root'})    = ($drupal_status_data =~ m/^ *Drupal root *: *(\S+?) *$/mi);
        ($drupal_status->{'site_path'})      = ($drupal_status_data =~ m/^ *Site path *: *(\S+?) *$/mi);
        ($drupal_status->{'site_files_path'}) = ($drupal_status_data =~ m/^ *File directory path *: *(\S+?) *$/mi);
        ($drupal_status->{'site_private_files_path'}) = ($drupal_status_data =~ m/^ *Private file directory path *: *(\S+?) *$/mi);
        
        # adjust path
        if ($drupal_status->{'site_files_path'} !~ m/^\//)
        {
            $drupal_status->{'site_files_path'} =
                "$drupal_status->{'drupal_root'}/$drupal_status->{'site_files_path'}";
        }
        if ($drupal_status->{'site_path'} !~ m/^\//)
        {
            $drupal_status->{'site_path'} =
                "$drupal_status->{'drupal_root'}/$drupal_status->{'site_path'}";
        }
        if ($drupal_status->{'site_private_files_path'} && ($drupal_status->{'site_private_files_path'} !~ m/^\//))
        {
            $drupal_status->{'site_private_files_path'} =
                "$drupal_status->{'drupal_root'}/$drupal_status->{'site_private_files_path'}";
        }
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
            warn "  $key => " . ($value || '') . "\n";
        }
        warn "----------\n";
    }
    
    return $drupal_status;
}


=pod

=head2 GetCoreStatus

B<Description>: Return developpment Drupal informations.

B<ArgsCount>: 1

=over 4

=item $drupal_status_data: (string) (R)

Drush status output.

=back

B<Return>: (hash ref)

Developpment informations.

=cut

sub GetCoreStatus
{
    my ($site_alias, $access_config) = @_;
    
    my $command = "$drupal_p2s::DRUSH_PATH $site_alias status --show-passwords";
    if ($access_config)
    {
        # get drush status (through ssh)
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
    }
    if ($DEBUG)
    {
        print "COMMAND:\n$command\n"; #+debug
    }
    my $core_version_data = `$command 2>&1`;
    if ($?)
    {
        confess "ERROR: an error occurred while executing:\n$command\n\n$core_version_data\n";
    }

    my $status = ParseDrupalStatus($core_version_data);

    return $status;
}


=pod

=head2 GetModules

B<Description>: Return Drupal modules informations.

B<ArgsCount>: 1-2

=over 4

=item $site_alias: (string) (R)

Site drush alias.

=back

B<Return>: (hash ref)
A hash containing modules and themes informations. Example of content:
    {
        'rules' => {
            'version' => '7.x-2.7',
            'status' => 'Enabled',
            'name' => 'Rules (rules)',
            'type' => 'Module',
            'package' => 'Rules'
        },
        'features' => {
            'version' => '7.x-2.2',
            'status' => 'Disabled',
            'name' => 'Features (features)',
            'type' => 'Module',
            'package' => 'Features'
        },
            'zen' => {
            'version' => '7.x-5.5',
            'status' => 'Enabled',
            'name' => 'Zen (zen)',
            'type' => 'Theme',
            'package' => 'Other'
        },
    };

=cut

sub GetModules
{
    my ($site_alias, $access_config) = @_;

    my $command = "$drupal_p2s::DRUSH_PATH $site_alias pm-list --format=json --no-core";
    if ($access_config)
    {
        # get drush status (through ssh)
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
    }
    if ($DEBUG)
    {
        print "COMMAND:\n$command\n"; #+debug
    }
    my $module_data = `$command 2>&1`;
    if ($?)
    {
        confess "ERROR: an error occurred while executing:\n$command\n\n$module_data\n";
    }

    my $module_data = from_json($module_data);
    
    return $module_data;
}


=pod

=head2 IsModuleAvailable

B<Description>: .

B<ArgsCount>: 1-2

=over 4

=item $site_alias: (string) (R)

Site drush alias.

=back

B<Return>: (boolean)

=cut

sub IsModuleAvailable
{
    my ($module_name, $module_data, $module_type, $module_status) = @_;

    if (!$module_name)
    {
        confess "ERROR: Missing module name!\n";
    }

    if (!$module_data || ('HASH' ne ref($module_data)))
    {
        confess "ERROR: Missing status hash!\n";
    }

    if (!$module_type)
    {
        $module_type = $drupal_p2s::MODULE_TYPE_MODULE;
    }
    
    my $module_available = 0;
    if (exists($module_data->{$module_name})
        && ($module_type eq $module_data->{$module_name}->{'type'})
        && (!defined($module_status) || ($module_status eq $module_data->{$module_name}->{'status'})))
    {
        $module_available = 1;
    }
    
    return $module_available;
}


=pod

=head2 IsModuleEnabled

B<Description>: .

B<ArgsCount>: 1-2

=over 4

=item $site_alias: (string) (R)

Site drush alias.

=back

B<Return>: (boolean)

=cut

sub IsModuleEnabled
{
    my ($module_name, $module_data, $module_type) = @_;
    return IsModuleAvailable($module_name, $module_data, $module_type, $MODULE_STATUS_ENABLED);
}


=pod

=head2 LockSite

B<Description>: .

B<ArgsCount>: 1-2

=over 4

=item $site_alias: (string) (R)

Site drush alias.

=back

B<Return>: (boolean)

=cut

sub LockSite
{
    my ($site_alias, $module_data, $access_config) = @_;
    
    if ($site_alias =~ m/\.$DRUSH_ALL_SUFFIX$/)
    {
        confess "ERROR: Invalid use of LockSite! Use LockSites for multiple sites!\n";
    }

    if (!$module_data || ('HASH' ne ref($module_data)))
    {
        $module_data = GetModules($site_alias, $access_config);
    }

    # check if we can put the site in read-only mode
    if (IsModuleEnabled('readonlymode', $module_data))
    {
        # yes, use read-only
        SetSiteVariable($site_alias, 'site_readonly', 1, $access_config);
    }
    else
    {
        # no, fallback to maintenance mode
        SetSiteVariable($site_alias, 'maintenance_mode', 1, $access_config);
    }
}


=pod

=head2 LockSites

B<Description>: .

B<ArgsCount>: 1-2

=over 4

=item $site_alias: (string) (R)

Site drush alias.

=back

B<Return>: (boolean)

=cut

sub LockSites
{
    my ($site_list, $access_config) = @_;
    
    if (!$site_list
        || (ref($site_list) && ('ARRAY' ne ref($site_list)))
       )
    {
        confess "ERROR: Missing or invalid site list!\n";
    }

    # if @*.all is used, get the list of sites
    if (!ref($site_list))
    {
        if ($site_list =~ m/^\@(\.+)\.$DRUSH_ALL_SUFFIX$/)
        {
            my $aliases = GetSiteAliases($1, $access_config);
            $site_list = [$aliases->{$_} keys(%$aliases)];
        }
        else
        {
            $site_list = [$site_list];
        }
    }
    
    foreach my $site_alias (@$site_list)
    {
        LockSite($site_alias, undef, $access_config);
    }
}


=pod

=head2 UnlockSite

B<Description>: .

B<ArgsCount>: 1-2

=over 4

=item $site_alias: (string) (R)

Site drush alias.

=back

B<Return>: (boolean)

=cut

sub UnlockSite
{
    my ($site_alias, $module_data, $access_config) = @_;
    
    if ($site_alias =~ m/\.$DRUSH_ALL_SUFFIX$/)
    {
        confess "ERROR: Invalid use of UnlockSite! Use UnlockSites for multiple sites!\n";
    }

    if (!$module_data || ('HASH' ne ref($module_data)))
    {
        $module_data = GetModules($site_alias, $access_config);
    }

    # check if read-only module is available
    if (IsModuleEnabled('readonlymode', $module_data))
    {
        # yes, unset read-only
        SetSiteVariable($site_alias, 'site_readonly', 0, $access_config);
    }

    # unset maintenance mode
    SetSiteVariable($site_alias, 'maintenance_mode', 0, $access_config);
}


=pod

=head2 UnlockSites

B<Description>: .

B<ArgsCount>: 1-2

=over 4

=item $site_alias: (string) (R)

Site drush alias.

=back

B<Return>: (boolean)

=cut

sub UnlockSites
{
    my ($site_list, $access_config) = @_;
    
    if (!$site_list
        || (ref($site_list) && ('ARRAY' ne ref($site_list)))
       )
    {
        confess "ERROR: Missing or invalid site list!\n";
    }

    # if @*.all is used, get the list of sites
    if (!ref($site_list))
    {
        if ($site_list =~ m/^\@(\.+)\.$DRUSH_ALL_SUFFIX$/)
        {
            my $aliases = GetSiteAliases($1, $access_config);
            $site_list = [$aliases->{$_} keys(%$aliases)];
        }
        else
        {
            $site_list = [$site_list];
        }
    }
    
    foreach my $site_alias (@$site_list)
    {
        UnlockSite($site_alias, undef, $access_config);
    }
}


=pod

=head2 GetSiteVariable

B<Description>: Get a drupal site variable.

B<ArgsCount>: 3-4

=over 4

=item $site_alias: (string) (R)

Drush site alias.

=item $variable: (string) (R)

Variable name.

=item $value: (string) (R)

Variable value.

=item $access_config: (hash) (O)

Remote config to process on a remote server.

=back

B<Return>: nothing

=cut

sub GetSiteVariable
{
    my ($alias, $variable, $access_config) = @_;

    if (!$alias)
    {
        confess "ERROR: Missing site alias!\n";
    }

    if (!defined($variable))
    {
        confess "ERROR: Missing variable name!\n";
    }

    # get variable
    my $command = "$drupal_p2s::DRUSH_PATH $alias vget --exact --yes $variable";
    if ($access_config)
    {
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
    }
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }

    my $variable_data = `$command 2>&1`;
    if ($?)
    {
        confess "ERROR: an error occurred while executing:\n$command\n\n$variable_data\n";
    }
    
    # remove label
    $variable_data =~ s/^$variable:\s*//;
    # remove quote for strings
    $variable_data =~ s/^'(.*)'$/$1/;

    return $variable_data;
}


=pod

=head2 SetSiteVariable

B<Description>: Set a drupal site variable.

B<ArgsCount>: 3-4

=over 4

=item $site_alias: (string) (R)

Drush site alias.

=item $variable: (string) (R)

Variable name.

=item $value: (string) (R)

Variable value.

=item $access_config: (hash) (O)

Remote config to process on a remote server.

=back

B<Return>: nothing

=cut

sub SetSiteVariable
{
    my ($alias, $variable, $value, $access_config) = @_;

    if (!$alias)
    {
        confess "ERROR: Missing site alias!\n";
    }

    if (!defined($variable) || !defined($value))
    {
        confess "ERROR: Missing variable name or value!\n";
    }

    # set variable
    my $command = "$drupal_p2s::DRUSH_PATH $alias vset --always-set --exact --yes $variable $value";
    if ($access_config)
    {
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
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
            confess "ERROR: An error occurred while setting drupal $alias site '$variable' variable to '$value':\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while setting drupal $alias site '$variable' variable to '$value'!\n";
        }
    }
}


=pod

=head2 GetRemoteSSHCommandLine

B<Description>: Returns the command line to run SSH on the remote server.

B<ArgsCount>: 1-2

=over 4

=item $config_hash: (string) (R)

Selected configuration.

=item $include_host_user: (boolean) (O)

If set to true, the username@host argument is added to the command line.

=back

B<Return>: (string)

The command line to run SSH on the target host. SHH commands can be appended.

=cut

sub GetRemoteSSHCommandLine
{
    my ($config_hash, $include_host_user) = @_;
    
    my $authentication = '';
    my $ssh_port   = '';

    if (($config_hash->{'password'}) && ($config_hash->{'identity'}))
    {
        confess "ERROR: Invalid configuration for remote host! Only a password OR an identity file should be provided, not both!\n";
    }
    elsif ($config_hash->{'password'})
    {
        $authentication = "-o PasswordAuthentication '$config_hash->{'password'}'";
    }
    elsif ($config_hash->{'identity'})
    {
        $authentication = "-i " . $config_hash->{'identity'};
    }

    if ($config_hash->{'port'})
    {
        $ssh_port = '-p ' . $config_hash->{'port'};
    }

    my $command = $drupal_p2s::SSH_PATH . ' ';

    if ($include_host_user)
    {
        $command .= $config_hash->{'user'} . "@" . $config_hash->{'host'} . ' ';
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
    my ($config_hash, $local_file, $remote_file) = @_;
    
    my $authentication = '';
    my $ssh_port   = '';

    if (($config_hash->{'password'}) && ($config_hash->{'identity'}))
    {
        confess "ERROR: Invalid configuration for remote host! Only a password OR an identity file should be provided, not both!\n";
    }
    elsif ($config_hash->{'password'})
    {
        $authentication = "-o PasswordAuthentication '$config_hash->{'password'}'";
    }
    elsif ($config_hash->{'identity'})
    {
        $authentication = "-i " . $config_hash->{'identity'};
    }
    
    if ($config_hash->{'port'})
    {
        $ssh_port = '-P ' . $config_hash->{'port'};
    }

    my $command = "$drupal_p2s::SCP_PATH -B -C $ssh_port $authentication '$local_file' " . $config_hash->{'user'} . "@" . $config_hash->{'host'} . ":$remote_file";

    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }

    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while transfering '$local_file' onto remote server:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while transfering '$local_file' onto remote server!\n";
        }
    }
}


=pod

=head2 SwapSymLinks

B<Description>: .

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=back

B<Return>: nothing

=cut

sub SwapSymLinks
{
    my ($parameters) = @_;

    # get stage link target
    my $command = "readlink $drupal_s2p::CONFIG{'stage_link'}";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $current_stage_link = `$command 2>&1`;
    if ($?)
    {
        confess "ERROR: an error occurred while executing:\n$command\n\n$current_stage_link\n";
    }
    $current_stage_link =~ s/^[\s\n\r]*//g;
    $current_stage_link =~ s/[\s\n\r]*$//g;

    # get prod link target
    $command = "readlink $drupal_s2p::CONFIG{'prod_link'}";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $current_prod_link = `$command 2>&1`;
    if ($?)
    {
        confess "ERROR: an error occurred while executing:\n$command\n\n$current_prod_link\n";
    }
    $current_prod_link =~ s/^[\s\n\r]*//g;
    $current_prod_link =~ s/[\s\n\r]*$//g;
    
    if (!$current_stage_link
        || !$current_prod_link
        || ($current_stage_link eq $current_prod_link))
    {
        confess "ERROR: Invalid stage or production link! Please check the configuration (stage='$drupal_s2p::CONFIG{'stage_link'}', prod='$drupal_s2p::CONFIG{'prod_link'}') and the links themselves.\n";
    }

    # swap links
    $command = "ln -nfs $current_prod_link $drupal_s2p::CONFIG{'stage_link'}";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while updating stage link:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while updating stage link!\n";
        }
    }
    $command = "ln -nfs  $current_stage_link  $drupal_s2p::CONFIG{'prod_link'}";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while updating prod link:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while updating prod link!\n";
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

=head2 DumpSite

B<Description>: Dumps dev site database and return the dump file name.

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=back

B<Return>: (string)

Dump file path.

=cut

sub DumpSite
{
    my ($site_alias) = @_;

    my $site_name = $site_alias;
    $site_name =~ s/^\@//; # remove alias prefix
    $site_name =~ s/\W/_/g; # make sure we only have valid characters
    my $sql_dump_file = "$drupal_p2s::TEMP_PATH/" . $site_name . "_dump.sql";

    if (-e $sql_dump_file)
    {
        # remove previous dump
        if (!unlink($sql_dump_file))
        {
            confess "ERROR: Failed to remove previous database dump '$sql_dump_file'!\nerrno: $!\n";
        }
    }

    # use drush to dump database
    my $command = "$drupal_p2s::DRUSH_PATH $site_alias sql-dump --result-file='$sql_dump_file' --yes";
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

=head2 LoadDumpOnSite

B<Description>: .

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=item $site_status: (hash ref) (R)

Hash of drupal stage status.

=item $sql_dump_file: (string) (R)

Path of the SQL dump file to load into database.

=back

B<Return>: nothing

=cut

sub LoadDumpOnSite
{
    my ($site_alias, $site_status, $sql_dump_file, $access_config) = @_;

    # use drush to load database dump
    my $command = "$drupal_p2s::DRUSH_PATH $site_alias sql-cli --yes --extra=";

    if ($access_config)
    {
        # transfer dump file to remote host
        SCPLocalToRemoteFile($access_config, $sql_dump_file, $sql_dump_file);

        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
    }

    if ($site_status->{'db_driver'} =~ m/pg?sql/i)
    {
        $command .= "'--file=\"$sql_dump_file\"'";
    }
    else
    {
        #+FIXME: for redhat, escape spaces
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
            confess "ERROR: An error occurred while loading database dump onto $site_alias:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while loading database dump onto $site_alias!\n";
        }
    }
    
    if ($access_config)
    {
        # remove remote file
        $command = GetRemoteSSHCommandLine($access_config, 1);
        $command .= " rm -f '$sql_dump_file'";
        $exist_status = system($command);
        if ($exist_status)
        {
            if (-1 == $exist_status)
            {
                confess "ERROR: An error occurred while trying to remove remote database dump:\n$!\n";
            }
            else
            {
                confess "ERROR: An error occurred while trying to remove remote database dump!\n";
            }
        }
    }
}


=pod

=head2 ReplaceDBStrings

B<Description>: .

B<Return>: nothing

=cut

sub ReplaceDBStrings
{
    my ($site_status, $replacement_hash) = @_;

    # replace command
    my $command = "php -f $drupal_p2s::SEARCH_REPLACE_DB_PATH -- ";

    if ($site_status->{'db_driver'} =~ m/pg?sql/i)
    {
        $command .= "-d pgsql ";
    }
    else
    {
        $command .= "-d mysql ";
    }
    $command .= "-h $site_status->{'db_hostname'} -n $site_status->{'db_name'} -u $site_status->{'db_username'} -p '$site_status->{'db_password'}'";

    while (my ($search_string, $replace_string) = each %{$replacement_hash})
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

=head2 UpdateDatabase

B<Description>: .

B<Return>: nothing

=cut

sub UpdateDatabase
{
    my ($site_alias, $access_config) = @_;
    
    # run updatedb
    my $command = "$drupal_p2s::DRUSH_PATH $site_alias updatedb --yes";
    if ($access_config)
    {
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
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
            confess "ERROR: An error occurred while updating $site_alias database:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while updating $site_alias database!\n";
        }
    }
}


=pod

=head2 RunRSyncForDirectory

B<Description>: .

B<Return>: nothing

=cut

sub RunRSyncForDirectory
{
    my ($source_path, $source_access_config, $target_path, $target_access_config) = @_;

    #+FIXME: support for file backup
    
    if (!$source_path || !$target_path || ($source_path !~ m/\w+/) || ($target_path !~ m/\w+/))
    {
        confess "ERROR: invalid RunDevToStageRSyncForDirectory call: missing a path argument!\n";
    }

    if ($source_access_config && $target_access_config)
    {
        confess "ERROR: rsync 2 remote directories is not supported yet!\n";
    }

    if ($source_access_config)
    {
        $source_path = $source_access_config->{'user'} . '@' . $source_access_config->{'host'} . ':' . $source_path;
    }
    elsif (!-e $source_path)
    {
        confess "ERROR: source directory '$source_path' does not exist!\n";
    }

    if ($target_access_config)
    {
        $target_path = $target_access_config->{'user'} . '@' . $target_access_config->{'host'} . ':' . $target_path;
    }
    elsif (!-e $target_path)
    {
        confess "ERROR: target directory '$target_path' does not exist!\n";
    }

    # run rsync
    my @rsync_args = (
        "--verbose",
        "--checksum",
        "--recursive",
        "--copy-unsafe-links",
#        "--keep-dirlinks",
#        "--times",
        "--exclude=.git",
        "--exclude=.svn",
#        "--perms",
        "--delete-after",
        "--force",
        "--compress",
        "--skip-compress=zip,gz,tgz,tbz,bzip,bz2,jpg,jpeg,png,ogg,mp[34],mpeg,avi,mov,swf,mkv,rpm,deb",
    );

    if ($source_access_config)
    {
        push(@rsync_args, "--rsh=" . GetRemoteSSHCommandLine($source_access_config, 0));
    }
    elsif ($target_access_config)
    {
        push(@rsync_args, "--rsh=" . GetRemoteSSHCommandLine($target_access_config, 0));
    }

    push(@rsync_args, "$source_path/", "$target_path");
    
    if ($DEBUG)
    {
        my $command = $drupal_p2s::RSYNC_PATH . ' ' . join(' ', @rsync_args);
        warn "DEBUG: COMPILED COMMAND:\n$command\n"; #+debug
    }

    my $exist_status = system {$drupal_p2s::RSYNC_PATH} $drupal_p2s::RSYNC_PATH, @rsync_args;
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

=head2 RemoveDirectory

B<Description>: .

B<Return>: nothing

=cut

sub RemoveDirectory
{
    my ($path, $access_config) = @_;

    if (!$path || ($path !~ m/\w+/))
    {
        confess "ERROR: invalid RemoveDirectory call: missing path argument!\n";
    }

    if ($DEBUG)
    {
        print "Will remove" . ($access_config?' remote':'') . " directory '$path'\n"; #+debug
    }

    my $command = "rm -rf $path";
    if ($access_config)
    {
        # remove remote path
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
    }
    if ($DEBUG)
    {
        print "COMMAND:\n$command\n"; #+debug
    }

    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: Failed to remove directory '$path':\n$!\n";
        }
        else
        {
            confess "ERROR: Failed to remove directory '$path'!\n";
        }
    }
}


=pod

=head2 PrepareStageFileAccessForUpdate

B<Description>: .

B<Return>: nothing

=cut

sub PrepareStageFileAccessForUpdate
{
    my ($site_stage_config, $access_config) = @_;
    
    #
    my $command = "$site_stage_config->{'set_update_access'} $site_stage_config->{'user'}";
    if ($access_config)
    {
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
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
            confess "ERROR: An error occurred while preparing stage file access rights:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while preparing stage file access rights!\n";
        }
    }
}


=pod

=head2 AdjustStageFileAccessForWeb

B<Description>: .

B<Return>: nothing

=cut

sub AdjustStageFileAccessForWeb
{
    my ($site_stage_config, $access_config) = @_;

    # 
    my $command = "$site_stage_config->{'set_web_access'}";
    if ($access_config)
    {
        $command = GetRemoteSSHCommandLine($access_config, 1) . ' ' . $command;
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




return 1; # package return
__END__

=pod

=head1 AUTHORS

Valentin GUIGNON (Bioversity), v.guignon@cgiar.org

=head1 VERSION

Version 1.0.0

Date 05/02/2015

=cut
