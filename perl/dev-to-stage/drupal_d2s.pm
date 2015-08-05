=pod

=head1 NAME

drupal_d2s - Drupal Dev-to-Staging configuration file

=head1 SYNOPSIS

    use drupal_d2s;
    

=head1 REQUIRES

Perl5

=head1 EXPORTS

Nothing

=head1 DESCRIPTION

Contains Drupal Dev-to-Staging configuration.

=cut

package drupal_d2s;


use strict;
use warnings;




# Package constants
####################

=pod

=head1 CONSTANTS

B<$RSYNC_PATH>:  (string)

Path to rsync executable.

B<%CONFIG>: (hash)

Configuration hash.

=cut

our $D2S_VERSION            = 'Drupal Dev to Staging v1.2';
our $DEFAULT_LOG_FILE       = 'drupal_d2s.log';
our $RSYNC_PATH             = 'rsync';
our $SSH_PATH               = 'ssh';
our $SCP_PATH               = 'scp';
our $DRUSH_PATH             = 'drush';
our $SEARCH_REPLACE_DB_PATH = '/path_to/apps/Search-Replace-DB/srdb.cli.php';
our $TEMP_PATH              = '/tmp';
our $ES_INDEX_PREFIX        = 'elasticsearch_index_';

our %CONFIG = (
    'mgis' => {
        'host'       => '10.10.10.10',
        'port'       => 22,
        'user'       => 'guignon',
        'password'   => '',
        'identity'   => '/path_to/ssh_unprotected.key',
        'dev_drupal_path'   => '/path_to/drupal7',
        'dev_drupal_site'   => 'crop-diversity.org.mgis',
        'dev_drush_alias'   => '@dev.mgis',
        'replacements'      => {
            'dev.crop-diversity.org' => 'stage.crop-diversity.org',
            '/path_to/www-writable/crop-diversity.org/dev/mgis_private_files' => '/path_to/crop_diversity/stage/private_files/mgis_private_files',
        },
        'stage_drupal_path'   => '/path_to/drupal7_stage',
        'stage_drupal_site'   => 'crop-diversity.org.mgis',
        'stage_drush_alias'   => '@stage.mgis',
        'set_web_access'      => '/path_to/scripts/set_mgis_web_access',
        'set_user_access'     => '/path_to/scripts/set_mgis_user_access',
#        'es_index_suffixes'   => ['_accession_index'],
        'disable_modules'     => ['update', 'dblog', 'field_ui', 'openlayers_ui', 'form_builder_webform', 'form_builder', 'rules_admin'],
    },
);




return 1; # package return
__END__

=pod

=head1 AUTHORS

Valentin GUIGNON (Bioversity), v.guignon@cgiar.org

=head1 VERSION

Version 1.2.0

Date 18/11/2014

=cut
