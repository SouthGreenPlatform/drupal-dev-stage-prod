#!/usr/bin/env perl

=pod

=head1 NAME

drupal_s2p.pl - Drupal Staging-to-Prod script

=head1 SYNOPSIS

    drupal_s2p.pl -config mgis

=head1 REQUIRES

Perl5, rsync, ssh, drush (>=7), Search-Replace-DB (with PostgreSQL support)

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

use drupal_s2p;

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

=head2 GetSiteAliases

B<Description>: Return staging site informations.

B<ArgsCount>: 1

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=back

B<Return>: (hash ref)

Stage informations.

=cut

sub GetSiteAliases
{
    my ($parameters) = @_;

    my $command = "$drupal_s2p::DRUSH_PATH site-alias $drupal_s2p::CONFIG{'cropdiv'}->{'all_stage_drush_alias'} --fields=#name --format=csv";
    if ($DEBUG)
    {
        print "COMMAND:\n$command\n"; #+debug
    }
    my $site_raw_aliases = `$command`;

    # associative hash stage_site => prod_site
    my %site_aliases;
    if ($site_raw_aliases)
    {
        foreach my $site_alias (split(/[\s\r\n]+/, $site_raw_aliases))
        {
            if ($site_alias)
            {
                if (exists($drupal_s2p::CONFIG{'cropdiv'}->{'stage_to_prod_aliases'}->{'@' . $site_alias}))
                {
                    $site_aliases{'@' . $site_alias} = $drupal_s2p::CONFIG{'cropdiv'}->{'stage_to_prod_aliases'}->{'@' . $site_alias};
                }
                elsif ($site_alias =~ m/stage|staging/i)
                {
                    my $prod_alias = $site_alias;
                    $prod_alias =~ s/stage|staging/prod/i;
                    $site_aliases{'@' . $site_alias} = '@' . $prod_alias;
                }
                else
                {
                    confess "ERROR: No available prod alias for staging site '$site_alias'!\n";
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
    elsif ($drupal_status_data =~ m/^\s*Drupal version\s*:\s*(\d+\.\d+)/m)
    {
        $drupal_status->{'version'}     = $1;

        ($drupal_status->{'site_uri'})       = ($drupal_status_data =~ m/^\s*Site URI\s*:\s*(\S+)\s*$/m);
        ($drupal_status->{'db_driver'})      = ($drupal_status_data =~ m/^\s*Database driver\s*:\s*(\w+)/m);
        ($drupal_status->{'db_hostname'})    = ($drupal_status_data =~ m/^\s*Database hostname\s*:\s*(\w+)/m);
        ($drupal_status->{'db_username'})    = ($drupal_status_data =~ m/^\s*Database username\s*:\s*(\w+)/m);
        ($drupal_status->{'db_name'})        = ($drupal_status_data =~ m/^\s*Database name\s*:\s*(\w+)/m);
        ($drupal_status->{'db_status'})      = ($drupal_status_data =~ m/^\s*Database\s*:\s*(\w+)/m);
        ($drupal_status->{'bootstrap'})      = ($drupal_status_data =~ m/^\s*Drupal bootstrap\s*:\s*(\w+)/m);
        ($drupal_status->{'drupal_user'})    = ($drupal_status_data =~ m/^\s*Drupal user\s*:\s*([^\n\r]+)\s*$/m);
        ($drupal_status->{'drupal_theme'})   = ($drupal_status_data =~ m/^\s*Default theme\s*:\s*([^\n\r]+)\s*$/m);
        ($drupal_status->{'drupal_root'})    = ($drupal_status_data =~ m/^\s*Drupal root\s*:\s*(\S+)\s*$/m);
        ($drupal_status->{'site_path'})      = ($drupal_status_data =~ m/^\s*Site path\s*:\s*(\S+)\s*$/m);
        ($drupal_status->{'site_file_path'}) = ($drupal_status_data =~ m/^\s*File directory path\s*:\s*(\S+)\s*$/m);
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
    my ($parameters, $stage_alias) = @_;

    my $command = "$drupal_s2p::DRUSH_PATH $stage_alias status";
    if ($DEBUG)
    {
        print "COMMAND:\n$command\n"; #+debug
    }
    my $core_version_data = `$command 2>&1`;
    
    my $stage_status = ParseDrupalStatus($core_version_data);
    
    if (%$stage_status)
    {
        $command = "$drupal_s2p::DRUSH_PATH $stage_alias ev 'global \$databases; echo \$databases[\"default\"][\"default\"][\"password\"];'";
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

=head2 SetSiteOffline

B<Description>: Set a drupal site offline (or online according to the parameters).

B<ArgsCount>: 2-3

=over 4

=item $parameters: (hash) (R)

Hash of parameters: see file description.

=item $alias: (string) (R)

Drush site alias.

=item $offline_status: (boolean) (O)

Offline status. Can be 0 or 1. Default: 1 (=set offline).

=back

B<Return>: nothing

=cut

sub SetSiteOffline
{
    my ($parameters, $alias, $offline_status) = @_;

    if (!$alias)
    {
        confess "ERROR: Missing site alias!\n";
    }

    if (!defined($offline_status) || ($offline_status !~ m/^[01]$/))
    {
        # offline by default
        $offline_status = 1;
    }

    # set drush online status
    my $command = "$drupal_s2p::DRUSH_PATH $alias vset --always-set maintenance_mode $offline_status --yes";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $exist_status = system($command);
    if ($exist_status)
    {
        if (-1 == $exist_status)
        {
            confess "ERROR: An error occurred while setting drupal $alias site offline:\n$!\n";
        }
        else
        {
            confess "ERROR: An error occurred while setting drupal $alias site offline!\n";
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
    my $command = "readlink $drupal_s2p::CONFIG{'cropdiv'}->{'stage_link'}";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $current_stage_link = `$command`;
    $current_stage_link =~ s/^[\s\n\r]*//g;
    $current_stage_link =~ s/[\s\n\r]*$//g;

    # get prod link target
    $command = "readlink $drupal_s2p::CONFIG{'cropdiv'}->{'prod_link'}";
    if ($DEBUG)
    {
        warn "DEBUG: COMMAND:\n$command\n"; #+debug
    }
    my $current_prod_link = `$command`;
    $current_prod_link =~ s/^[\s\n\r]*//g;
    $current_prod_link =~ s/[\s\n\r]*$//g;
    
    if (!$current_stage_link
        || !$current_prod_link
        || ($current_stage_link eq $current_prod_link))
    {
        confess "ERROR: Invalid stage or production link! Please check the configuration (stage='$drupal_s2p::CONFIG{'cropdiv'}->{'stage_link'}', prod='$drupal_s2p::CONFIG{'cropdiv'}->{'prod_link'}') and the links themselves.\n";
    }

    # swap links
    $command = "ln -nfs $current_prod_link $drupal_s2p::CONFIG{'cropdiv'}->{'stage_link'}";
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
    $command = "ln -nfs  $current_stage_link  $drupal_s2p::CONFIG{'cropdiv'}->{'prod_link'}";
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

=head2 ReplaceDBStrings

B<Description>: .

B<Return>: nothing

=cut

sub ReplaceDBStrings
{
    my ($parameters, $stage_status) = @_;

    # replace command
    my $command = "php -f $drupal_s2p::SEARCH_REPLACE_DB_PATH -- ";

    if ($stage_status->{'db_driver'} =~ m/pg?sql/i)
    {
        $command .= "-d pgsql ";
    }
    else
    {
        $command .= "-d mysql ";
    }
    $command .= "-h $stage_status->{'db_hostname'} -n $stage_status->{'db_name'} -u $stage_status->{'db_username'} -p '$stage_status->{'db_password'}'";

    while (my ($search_string, $replace_string) = each %{$drupal_s2p::CONFIG{'cropdiv'}->{'replacements'}})
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




# Script options
#################

=pod

=head1 OPTIONS

    drupal_s2p.pl [-help | -man]

    drupal_s2p.pl -p

    drupal_s2p.pl -r

=head2 Parameters

=over 4

=item B<-help>:

Prints a brief help message and exits.

=item B<-man>:

Prints the manual page and exits.

=item B<-debug>:

Executes the script in debug mode.

=item B<-p> (flag)

Proceed to transfer staging site into prod.

=item B<-r> (flag)

Revert transfer and put back original prod without database modifications.

=back

=cut


# CODE START
#############

# options processing
my ($man, $help, $debug, $proceed, $revert) = (0, 0, 0, 0, 0);

print "$drupal_s2p::D2S_VERSION\n\n";

# parse options and print usage if there is a syntax error.
GetOptions('help|?'     => \$help,
           'man'        => \$man,
           'debug'      => \$debug,
           'p'          => \$proceed,
           'r'          => \$revert,
) or pod2usage(1);
if ($help) {pod2usage('-verbose' => 1, '-exitval' => 0);}
if ($man) {pod2usage('-verbose' => 2, '-exitval' => 0);}

if (!($proceed || $revert) || ($proceed && $revert))
{
    pod2usage(1);
}

# change debug mode if requested/forced
$DEBUG ||= $debug;

my $parameters = {};

if ($revert)
{
    # just swap symlinks
    SwapSymLinks();
}
else
{
    my $aliases = GetSiteAliases($parameters);
    while (my ($stage_alias, $prod_alias) = each(%$aliases))
    {
        if ($DEBUG)
        {
            warn "Getting stage site '$stage_alias' status\n"; #+debug
        }
        my $stage_status = GetStageCoreStatus($parameters, $stage_alias);

        # run DB replacements
        ReplaceDBStrings($parameters, $stage_status);
    }

    # put prod site offline
    SetSiteOffline($parameters, $drupal_s2p::CONFIG{'cropdiv'}->{'all_prod_drush_alias'}, 1);

    # swap symlinks
    SwapSymLinks();

    # put back stage (old prod) online
    SetSiteOffline($parameters, $drupal_s2p::CONFIG{'cropdiv'}->{'all_stage_drush_alias'}, 0);
    #+FIXME: also remove read-only mode
}


exit(0);

__END__
# CODE END
###########

=pod

=head1 AUTHORS

Valentin GUIGNON (Bioversity), v.guignon@cgiar.org

=head1 VERSION

Version 1.1.0

Date 30/10/2014

=cut
