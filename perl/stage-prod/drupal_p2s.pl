#!/usr/bin/env perl

=pod

=head1 NAME

drupal_dsp_config.pl - Drupal Prod-to-Stage script

=head1 SYNOPSIS

    drupal_dsp_config.pl -config mgis

=head1 REQUIRES

Perl5, rsync, ssh, drush (>=7), Search-Replace-DB (with PostgreSQL support)

=head1 DESCRIPTION

This script can be used to copy one or several production sites into staging.
During the process, each production site copied will be turned in read-only mode
(or offline if read-only mode not available) during the database and file copy.
Once files are copied and the database has been duplicated, the production site
is turned back online automatically unless '-off' command line argument is used.
The new staging database is automatically adjusted to stage settings (database
string replacements).

Note: the Drupal core version on the staging site will remain unchanged. If it
is a more recent version than the prod one, the new staging site data will be
updated to that version.

=cut

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";

use Carp qw (cluck confess croak);

use Getopt::Long;
use Pod::Usage;

use drupal_dsp;
use drupal_dsp_config;

++$|; #no buffering




# Script options
#################

=pod

=head1 OPTIONS

    drupal_dsp_config.pl [-help | -man]

    drupal_dsp_config.pl -list

    drupal_dsp_config.pl [-config <CONFIG>] -site <SITE> [-offline] [-debug | -verbose [-verbose]]

=head2 Parameters

=over 4

=item B<-help>:

Prints a brief help message and exits.

=item B<-man>:

Prints the manual page and exits.

=item B<-debug>:

Executes the script in debug mode.

=item B<-config> (string)

Configuration set to use.

=item B<-site> (string)

Site to process. Use '-list' to get the list of available sites.

=item B<-list>

Lists available sites.

=item B<-offline>

Keeps production site offline after transfer.

=back

=cut


# CODE START
#############

# options processing
my ($man, $help, $debug, $verbose) = (0, 0, 0, 0);
my ($config, $site, $list_sites, $stay_offline);

print "$drupal_dsp_config::D2S_VERSION\n\n";

# parse options and print usage if there is a syntax error.
GetOptions('help|?'      => \$help,
           'man'         => \$man,
           'debug'       => \$debug,
           'verbose+'    => \$verbose,
           'c|config=s'  => \$config,
           's|site=s'    => \$site,
           'list'        => \$list_sites,
           'off|offline' => \$stay_offline,
) or pod2usage(1);
if ($help) {pod2usage('-verbose' => 1, '-exitval' => 0);}
if ($man) {pod2usage('-verbose' => 2, '-exitval' => 0);}

# no config, use default
$config ||= $drupal_dsp::DEFAULT_CONFIG;

# change debug mode if requested/forced
$drupal_dsp_config::DEBUG ||= $debug;
if ($drupal_dsp_config::DEBUG)
{$verbose = 10;}

# get the list of available sites
my $site_aliases = GetSiteAliases();
if ($list_sites)
{
    ShowSiteList($site_aliases);
    exit(0);
}

# make sure a site has been specified
if (!$site)
{
    pod2usage(1);
}

# see what to process
my @sites_to_process = ($site);
if ($site eq 'all')
{
    @sites_to_process = keys(%$site_aliases);
}

# process each site, one by one
foreach $site (@sites_to_process)
{
    # global site eval
    eval
    {
        print "Processing site '$site'...\n";

        # make sure specified site exists and is available in stage and prod versions
        if (!exists($site_aliases->{$site})
            || (2 != grep {/^(?:stage|prod)$/} @{$site_aliases->{$site}})) {
            confess "Invalid site! Please check site list and make sure both stage and prod settings are available.\n";
        }

        if ($verbose)
        {warn "Getting stage site status\n";}
        my $stage_status = GetCoreStatus($drupal_dsp::DRUSH_STAGE_PREFIX . $site);

        if ($verbose)
        {warn "Getting prod site status\n";}
        my $prod_status  = GetCoreStatus($drupal_dsp::DRUSH_PROD_PREFIX . $site);

        # put stage site offline
        SetSiteVariable($drupal_dsp::DRUSH_STAGE_PREFIX . $site, 'maintenance_mode', 1);

        # put prod site in read-only/offline mode
        LockSite($drupal_p2s::DRUSH_PROD_PREFIX . $site);

        # make sure we'll put prod site back online if an error occurs
        my $prod_dump_filename;
        eval
        {
            # dump prod database
            $prod_dump_filename = DumpSite($drupal_dsp::DRUSH_PROD_PREFIX . $site);
            if ($drupal_dsp_config::DEBUG)
            {warn "Prod dumped into '$prod_dump_filename'\n";}

            if ($verbose)
            {warn "RSync files...\n";}

            # sync prod files/modules/themes/libraries to stage
            if ($drupal_dsp_config::DEBUG)
            {warn "Prepare access rights for update...\n";}

            # -prepare access rights
            PrepareStageFileAccessForUpdate(
                $drupal_dsp_config::CONFIG{$config}->{'stage'}->{$site},
            #    $drupal_dsp_config::CONFIG{$config}->{'servers'}->{'stage_prod'},
            );

            # catch errors to restore access rights in case of error
            eval
            {
                # launch rsync on files directory (with access rights)
                if (1 < $verbose)
                {warn "-files ($prod_status->{'site_files_path'})\n";}
                if ($stage_status->{'site_files_path'} && $prod_status->{'site_files_path'})
                {
                    RunRSyncForDirectory(
                        "$prod_status->{'site_files_path'}", undef,
                        "$stage_status->{'site_files_path'}", undef
                    );
                }

                # launch rsync on private files directory (with access rights)
                if (1 < $verbose)
                {warn "-private files ($prod_status->{'site_private_files_path'})\n";}
                if ($stage_status->{'site_private_files_path'} && $prod_status->{'site_private_files_path'})
                {
                    RunRSyncForDirectory(
                        "$prod_status->{'site_private_files_path'}", undef,
                        "$stage_status->{'site_private_files_path'}", undef
                    );
                }
            };
            # warn errors
            if ($@)
            {
                cluck "WARNING: Failed to sync file directories:\n$@";
            }

            if ($drupal_dsp_config::DEBUG)
            {warn "Adjust access rights for web...\n";}

            # adjust access rights
            AdjustStageFileAccessForWeb(
                $drupal_dsp_config::CONFIG{$config}->{'stage'}->{$site},
            #    $drupal_dsp_config::CONFIG{$config}->{'servers'}->{'stage_prod'},
            );


            if ($stage_status->{'site_path'}
                && $prod_status->{'site_path'})
            {
                # launch rsync on libraries, themes and modules
                foreach my $subdir ('libraries', 'themes', 'modules')
                {
                    if (1 < $verbose)
                    {warn "-$subdir ($prod_status->{'site_path'}/$subdir)\n";}
                    # catch directories that fail
                    eval
                    {
                        # directory exists on prod?
                        if (-e "$prod_status->{'site_path'}/$subdir")
                        {
                            # yes, missing on stage?
                            if (!-e "$stage_status->{'site_path'}/$subdir")
                            {
                                # missing, create it
                                mkdir "$stage_status->{'site_path'}/$subdir"
                                    or confess "Failed to create directory '$stage_status->{'site_path'}/$subdir': $!\n";
                            }

                            # sync
                            RunRSyncForDirectory(
                                "$prod_status->{'site_path'}/$subdir", undef,
                                "$stage_status->{'site_path'}/$subdir", undef
                            );
                        }
                        elsif (-e "$stage_status->{'site_path'}/$subdir")
                        {
                            # only in stage? remove it
                            RemoveDirectory("$stage_status->{'site_path'}/$subdir");
                        }
                    };
                    
                    # show errors
                    if ($@)
                    {
                        cluck "WARNING: Failed to sync directory '$subdir':\n$@";
                    }
                }
            }

            if ($verbose)
            {warn "...files synchronized.\n";}
            
            #+FIXME: duplicate elasticsearch index if available
        };
        my $transfer_error = $@;

        # put back prod site online (unless told not to do so)
        if (!$stay_offline)
        {
            UnlockSite($drupal_dsp::DRUSH_PROD_PREFIX . $site);
        }

        # report error if some
        if ($transfer_error)
        {
            # rethrow error
            confess $@;
        }
        elsif (!$prod_dump_filename)
        {
            confess "ERROR: No dump filename found! Database dump failed.\n";
        }


        # load prod dump into stage
        LoadDumpOnSite($drupal_dsp::DRUSH_STAGE_PREFIX . $site, $stage_status, $prod_dump_filename);

        # replace database strings in stage
        # reverts stage-to-prod hash into prod-to-stage hash
        my $p2s_replacement_hash = {
            map
                { $drupal_dsp_config::CONFIG{$config}->{'replacements'}->{'stage_to_prod'}->{$site}->{$_} => $_ }
                keys(%{$drupal_dsp_config::CONFIG{$config}->{'replacements'}->{'stage_to_prod'}->{$site}})
        };
        ReplaceDBStrings($stage_status, $p2s_replacement_hash);

        # run stage update (update "old" prod core to "new" stage core in case versions differ)
        UpdateDatabase($drupal_dsp::DRUSH_STAGE_PREFIX . $site);

        # put stage site back online
        UnlockSite($drupal_dsp::DRUSH_STAGE_PREFIX . $site);
    }; # global site eval end

    if ($@)
    {
        cluck "WARNING: an error occurred while processing '$site':\n" . $@;
    }
}

exit(0);

__END__
# CODE END
###########

=pod

=head1 AUTHORS

Valentin GUIGNON (Bioversity), v.guignon@cgiar.org

=head1 VERSION

Version 1.3.0

Date 25/03/2015

=cut
