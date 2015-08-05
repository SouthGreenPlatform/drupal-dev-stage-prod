=pod

=head1 NAME

drupal_dsp_config - Drupal Dev-Stage-Prod configuration file

=head1 SYNOPSIS

    use drupal_dsp_config;
    

=head1 REQUIRES

Perl5

=head1 EXPORTS

Nothing

=head1 DESCRIPTION

Contains Drupal Dev-Stage-Prod configuration.

=cut

package drupal_dsp_config;


use strict;
use warnings;




# Package constants
####################

=pod

=head1 CONSTANTS

B<$DEFAULT_LOG_FILE>: (string)

Name of default log file.

B<$RSYNC_PATH>:  (string)

Path to rsync executable.

B<$SSH_PATH>:  (string)

Path to ssh executable.

B<$SCP_PATH>:  (string)

Path to scp executable.

B<$DRUSH_PATH>:  (string)

Path to drush executable.

B<$SEARCH_REPLACE_DB_PATH>:  (string)

Path to srdb.cli.php executable.

B<$TEMP_PATH>:  (string)

Path to temporary file directory.

B<%CONFIG>: (hash)

Configuration hash.
Key level 1: configuration set names.
Key level 1:
  'servers': server access config hash;
  'dev': dev server config items;
  'stage': stage server config items;
  'prod': prod server config items;
  'replacements': remplacement string sets from a server to another.

=cut

our $DEBUG                  = 0;
our $DEFAULT_LOG_FILE       = 'drupal_dsp.log';
our $RSYNC_PATH             = 'rsync';
our $SSH_PATH               = 'ssh';
our $SCP_PATH               = 'scp';
our $DRUSH_PATH             = 'drush';
our $SEARCH_REPLACE_DB_PATH = '/path_to/apps/Search-Replace-DB/srdb.cli.php';
our $TEMP_PATH              = '/tmp';

our %CONFIG = (
    'default' => {
        'servers' => {
            'stage_prod' => {
                'host'        => '10.10.10.10',
                'port'        => 22,
                'user'        => 'guignon',
                'password'    => '',
                'identity'    => '/path_to/ssh_unprotected.key',
            },
        },
        'dev' => {
            'link' => '/path_to/drupal7_dev',
        },
        'stage' => {
            'link'  => '/path_to/crop_diversity/stage',
            'cropdiv' => {
                'user'              => 'guignon',
                'set_web_access'    => '/path_to/scripts/set_cropdiv_web_access',
                'set_update_access' => '/path_to/scripts/set_cropdiv_user_access',
            },
            'mgis' => {
                'user'              => 'guignon',
                'set_web_access'    => '/path_to/scripts/set_mgis_web_access',
                'set_update_access' => '/path_to/scripts/set_mgis_user_access',
#                'es_index_suffixes' => ['_accession_index'],
                'disable_modules'   => ['update', 'dblog', 'field_ui', 'openlayers_ui', 'form_builder_webform', 'form_builder', 'rules_admin'],
                'enable_modules'    => [],
            },
        },
        'prod' => {
            'link' => '/path_to/crop_diversity/prod',
        },
        'replacements' => {
            'dev_to_stage' => {
                'cropdiv' => {
                    'dev.crop-diversity.org' => 'stage.crop-diversity.org',
                },
                'mgis' => {
                    'dev.crop-diversity.org' => 'stage.crop-diversity.org',
                    '/path_to/www-writable/crop-diversity.org/dev/mgis_private_files' => '/path_to/crop_diversity/stage/private_files/mgis_private_files',
                },
            },
            'stage_to_prod' => {
                'cropdiv' => {
                    'stage.crop-diversity.org' => 'www.crop-diversity.org',
                },
                'mgis' => {
                    'stage.crop-diversity.org' => 'www.crop-diversity.org',
                    '/path_to/crop_diversity/stage/private_files/mgis_private_files' => '/path_to/crop_diversity/prod/private_files/mgis_private_files',
                },
            },
        },
    },
);


return 1; # package return
__END__

=pod

=head1 AUTHORS

Valentin GUIGNON (Bioversity), v.guignon@cgiar.org

=head1 VERSION

Version 1.3.0

Date 25/03/2015

=cut
