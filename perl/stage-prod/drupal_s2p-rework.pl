#!/usr/bin/env perl

=pod

=head1 NAME

drupal_s2p.pl - Drupal Stage-to-Prod script

=head1 SYNOPSIS

    drupal_s2p.pl -p

=head1 REQUIRES

Perl5, rsync, ssh, drush (>=7), Search-Replace-DB (with PostgreSQL support)

=head1 DESCRIPTION

Script used to transfer current stage site into production by replacing what is
needed in the site (config, database, files).

=cut

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";

use Carp qw (cluck confess croak);

use Getopt::Long;
use Pod::Usage;

use drupal_dsp;
use drupal_p2s;

++$|; #no buffering




# Script global constants
##########################

=pod

=head1 CONSTANTS

B<$DEBUG>: (boolean)

When set to true, it enables debug mode.

=cut

our $DEBUG = 1;




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

=item B<-list>

List available sites.

=item B<-config> (string)

Select a specific configuration set of the config file instead of the 'default'
one.

=back

=cut


# CODE START
#############

# options processing
my ($man, $help, $debug, $verbose, $proceed, $revert) = (0, 0, 0, 0, 0, 0);
my ($config, $site, $list_sites);

print "$drupal_p2s::D2S_VERSION\n\n";

# parse options and print usage if there is a syntax error.
GetOptions('help|?'     => \$help,
           'man'        => \$man,
           'debug'      => \$debug,
           'verbose+'   => \$verbose,
           'c|config=s' => \$config,
           'list'       => \$list_sites,
           'p'          => \$proceed,
           'r'          => \$revert,
) or pod2usage(1);
if ($help) {pod2usage('-verbose' => 1, '-exitval' => 0);}
if ($man) {pod2usage('-verbose' => 2, '-exitval' => 0);}

# no config, use default
$config ||= 'default';

my $modules = GetModules('@stage.mgis'); #+debug
use Data::Dumper;
print Dumper($modules);


if (!($proceed || $revert) || ($proceed && $revert))
{
    pod2usage(1);
}

# change debug mode if requested/forced
$DEBUG ||= $debug;
if ($DEBUG)
{$verbose = 10;}

# get the list of available sites
my $site_aliases = GetSiteAliases();
if ($list_sites)
{
    ShowSiteList($site_aliases);
    exit(0);
}

# stage to prod or rvert changes?
if ($revert)
{
    # revert, just swap symlinks
    SwapSymLinks();
}
elsif ($proceed)
{
    my $site;
    # stage to prod
    foreach $site (keys(%$site_aliases))
    {
        if ($DEBUG)
        {
            warn "Getting stage site '$site' status\n"; #+debug
        }
        my $stage_status = GetCoreStatus($drupal_p2s::DRUSH_STAGE_PREFIX . $site);

        # run DB replacements
        # replace database strings in stage
        ReplaceDBStrings($stage_status, $drupal_p2s::CONFIG{$config}->{'replacements'}->{'stage_to_prod'});
    }

    # put prod sites in read-only/offline mode
    LockSites($drupal_p2s::DRUSH_PROD_PREFIX . $drupal_p2s::DRUSH_ALL_SUFFIX);

    # swap symlinks
    SwapSymLinks();

    # put back "new" stage (old prod) online
    UnlockSites($drupal_p2s::DRUSH_STAGE_PREFIX . $drupal_p2s::DRUSH_ALL_SUFFIX);

    # warn if some prod sites were set offline or in read-only mode
    foreach $site (keys(%$site_aliases))
    {
        if (GetSiteVariable($site, 'maintenance_mode'))
        {
            warn "WARNING: Production site '$site' is offline!\n";
        }
        elsif (GetSiteVariable($site, 'site_readonly'))
        {
            warn "WARNING: Production site '$site' is in read-only mode!\n";
        }
    }
}
else
{
    warn "WARNING: no operation selected! Nothing done.\n";
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
