<?php

define('_ATOM_DIR', '/atom/src');
define('_ETC_DIR', '/usr/local/etc');

function getenv_default($name, $default)
{
    $value = getenv($name);

    if (false === $value) {
        return $default;
    }

    return $value;
}

function getenv_or_fail($name)
{
    $value = getenv($name);

    if (false === $value) {
        echo "Environment variable {$name} is not defined!";

        exit(1);
    }

    return $value;
}

function get_host_and_port($value, $default_port)
{
    $parts = explode(':', $value);

    if (1 == count($parts)) {
        $parts[1] = $default_port;
    }

    return ['host' => $parts[0], 'port' => $parts[1]];
}

$CONFIG = [
    'atom.csrf_secret' => getenv_or_fail('ATOM_CSRF_SECRET'),
    'atom.default_culture' => getenv_default('ATOM_CULTURE', 'en_US'),
    'atom.elasticsearch_host' => getenv_or_fail('ELASTICSEARCH_HOST'),
    'atom.elasticsearch_port' => getenv_default('ELASTICSEARCH_PORT', 9200),
    'atom.memcached_host' => getenv_or_fail('MEMCACHED_HOST'),
    'atom.memcached_port' => getenv_default('MEMCACHED_PORT', 11211),
    'atom.gearmand_host' => getenv_or_fail('GEARMAND_HOST'),
    'atom.gearmand_port' => getenv_default('GEARMAND_PORT', 4730),
    'atom.mysql_dsn' => 'mysql:host=' . getenv_or_fail('DB_HOST') . ';port=' . getenv_default('DB_PORT', 3306) . ';dbname=' . getenv_or_fail('MYSQL_DATABASE') . ';charset=utf8mb4',
    'atom.mysql_username' => getenv_or_fail('MYSQL_USER'),
    'atom.mysql_password' => getenv_or_fail('MYSQL_PASSWORD'),
    'atom.debug_ip' => getenv_default('ATOM_DEBUG_IP', ''),
    'atom.static_url' => getenv_default('ATOM_STATIC_URL', ''),
    'php.max_execution_time' => getenv_default('ATOM_PHP_MAX_EXECUTION_TIME', '120'),
    'php.max_input_time' => getenv_default('ATOM_PHP_MAX_INPUT_TIME', '120'),
    'php.memory_limit' => getenv_default('ATOM_PHP_MEMORY_LIMIT', '512M'),
    'php.post_max_size' => getenv_default('ATOM_PHP_POST_MAX_SIZE', '72M'),
    'php.upload_max_filesize' => getenv_default('ATOM_PHP_UPLOAD_MAX_FILESIZE', '64M'),
    'php.max_file_uploads' => getenv_default('ATOM_PHP_MAX_FILE_UPLOADS', '20'),
    'php.date.timezone' => getenv_default('ATOM_TIMEZONE', 'America/Vancouver'),
];

//
// /apps/qubit/config/app.yml
//

$app_yml = <<<EOT
all:
  upload_limit: -1
  download_timeout: 10
  cache_engine: sfMemcacheCache
  cache_engine_param:
    host: {$CONFIG['atom.memcached_host']}
    port: {$CONFIG['atom.memcached_port']}
    prefix: atom
    storeCacheInfo: true
    persistent: true
  read_only: false
  htmlpurifier_enabled: false
  csp:
    response_header: Content-Security-Policy
    directives: >
      default-src 'self';
      font-src 'self' https://fonts.gstatic.com;
      form-action 'self';
      img-src 'self' {$CONFIG['atom.static_url']} https://*.googleapis.com https://*.gstatic.com *.google.com  *.googleusercontent.com data: https://www.gravatar.com/avatar/ https://*.google-analytics.com https://*.googletagmanager.com blob:;
      media-src 'self' {$CONFIG['atom.static_url']};
      script-src 'self' https://*.googletagmanager.com 'nonce' https://*.googleapis.com https://*.gstatic.com *.google.com https://*.ggpht.com *.googleusercontent.com blob:;
      style-src 'self' 'nonce' https://fonts.googleapis.com;
      worker-src 'self' blob:;
      connect-src 'self' https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com https://*.googleapis.com *.google.com https://*.gstatic.com  data: blob:;
      frame-ancestors 'self';
EOT;

@unlink(_ATOM_DIR.'/apps/qubit/config/app.yml');
file_put_contents(_ATOM_DIR.'/apps/qubit/config/app.yml', $app_yml);

//
// /apps/qubit/config/factories.yml
//

$factories_yml = <<<EOT
prod:
  storage:
    class: QubitCacheSessionStorage
    param:
      session_name: symfony
      session_cookie_httponly: true
      session_cookie_secure: true
      cache:
        class: sfMemcacheCache
        param:
          host: {$CONFIG['atom.memcached_host']}
          port: {$CONFIG['atom.memcached_port']}
          prefix: atom
          storeCacheInfo: true
          persistent: true

all:
  i18n:
    class: sfTranslateI18N
    param:
      cache:
        # class: sfAPCCache
        class: sfFileCache
        param:
          automatic_cleaning_factor: 0
          cache_dir: %SF_TEMPLATE_CACHE_DIR%
          lifetime: 86400
          prefix: %SF_APP_DIR%/template

  routing:
    class: QubitPatternRouting
    param:
      generate_shortest_url:            true
      extra_parameters_as_query_string: true
      # class: sfAPCCache
      cache: ~

  view_cache_manager:
    class: sfViewCacheManager
    param:
      cache_key_use_vary_headers: true
      cache_key_use_host_name:    true

  view_cache:
    # class: sfAPCCache
    class: sfFileCache
    param:
      automatic_cleaning_factor: 0
      cache_dir: %SF_TEMPLATE_CACHE_DIR%
      lifetime: 86400
      prefix: %SF_APP_DIR%/template

  user:
    class: myUser
    param:
      timeout: 1800

  logger:
    class: sfAggregateLogger
    param:
      level: warning
      loggers:
        sf_file_debug:
          class: sfFileLogger
          param:
            level: warning
            file: %SF_LOG_DIR%/%SF_APP%_%SF_ENVIRONMENT%.log
EOT;

@unlink(_ATOM_DIR.'/apps/qubit/config/factories.yml');
file_put_contents(_ATOM_DIR.'/apps/qubit/config/factories.yml', $factories_yml);

//
// /apps/qubit/config/gearman.yml
//

$gearman_yml = <<<EOT
all:
  servers:
    default: {$CONFIG['atom.gearmand_host']}:{$CONFIG['atom.gearmand_port']}

  worker_types:
    general:
      - arFindingAidJob
    acl:
      - arInheritRightsJob
    actor_relations:
      - arUpdateEsActorRelationsJob
    calculate_dates:
      - arCalculateDescendantDatesJob
    move:
      - arObjectMoveJob
    search_csv_export:
      - arInformationObjectCsvExportJob
    sword:
      - qtSwordPluginWorker
    publication_status:
      - arUpdatePublicationStatusJob
    file_import:
      - arFileImportJob
    xml_export:
      - arInformationObjectXmlExportJob
    xml_export_single_file:
      - arXmlExportSingleFileJob
    generate_csv_report:
      - arGenerateReportJob
    actor_csv_export:
      - arActorCsvExportJob
    actor_xml_export:
      - arActorXmlExportJob
    repository_csv_export:
      - arRepositoryCsvExportJob
    update_io_es_documents:
      - arUpdateEsIoDocumentsJob
    holdings_report:
      - arPhysicalObjectCsvHoldingsReportJob
    csv_validation:
      - arValidateCsvJob
    accession_csv_export:
      - arAccessionCsvExportJob
EOT;

@unlink(_ATOM_DIR.'/apps/qubit/config/gearman.yml');
file_put_contents(_ATOM_DIR.'/apps/qubit/config/gearman.yml', $gearman_yml);

//
// /apps/qubit/config/settings.yml
//

$settings_yml = <<<EOT
cli:
  .settings:
    logging_enabled:         true

prod:
  .settings:
    no_script_name:         true
    logging_enabled:        true
    cache:                  true

worker:
  .settings:
    logging_enabled:        true

all:
  .settings:
    # Form security secret (CSRF protection)
    csrf_secret:            {$CONFIG['atom.csrf_secret']}

    enabled_modules:        [default, aclGroup]

    # Output escaping settings
    escaping_strategy:      true
    escaping_method:        ESC_SPECIALCHARS

    i18n:                   true
    standard_helpers:       [Partial, Cache, I18N, Qubit]

    # Enable the database manager
    use_database:           true

    # The language is coded in two lowercase characters,
    # according to the ISO 639-1 standard, and the country
    # is coded in two uppercase characters, according to
    # the ISO 3166-1 standard.
    # Examples: en, en_US, es_ES, fr...
    default_culture:        {$CONFIG['atom.default_culture']}

    # List of supported timezones
    # http://www.php.net/manual/en/timezones.php
    default_timezone:       {$CONFIG['php.date.timezone']}

  .actions:
    error_404_module:       admin
    login_module:           user
    module_disabled_module: admin
    secure_module:          admin
EOT;

@unlink(_ATOM_DIR.'/apps/qubit/config/settings.yml');
file_put_contents(_ATOM_DIR.'/apps/qubit/config/settings.yml', $settings_yml);

//
// /config/appChallenge.yml
//

if (!file_exists(_ATOM_DIR.'/config/appChallenge.yml')) {
    copy(_ATOM_DIR.'/config/appChallenge.yml.tmpl', _ATOM_DIR.'/config/appChallenge.yml');
}

//
// /config/config.php
//

$config_php = <<<EOT
<?php

return [
    'all' => [
        'propel' => [
            'class' => 'sfPropelDatabase',
            'param' => [
                'encoding' => 'utf8mb4',
                'persistent' => true,
                'pooling' => true,
                'dsn' => '{$CONFIG['atom.mysql_dsn']}',
                'username' => '{$CONFIG['atom.mysql_username']}',
                'password' => '{$CONFIG['atom.mysql_password']}',
            ],
        ],
    ],
];
EOT;

@unlink(_ATOM_DIR.'/config/config.php');
file_put_contents(_ATOM_DIR.'/config/config.php', $config_php);

//
// /config/propel.ini
//

@unlink(_ATOM_DIR.'/config/propel.ini');
copy(_ATOM_DIR.'/config/propel.ini.tmpl', _ATOM_DIR.'/config/propel.ini');

//
// /config/search.yml
//

$search_yml = <<<EOT
all:
  batch_mode: true
  batch_size: 500
  server:
    host: {$CONFIG['atom.elasticsearch_host']}
    port: {$CONFIG['atom.elasticsearch_port']}
  index:
    name: atom
    configuration:
      settings:
        number_of_shards: 4
        number_of_replicas: 1
        mapping.total_fields.limit: 3000
        max_result_window: 10000
        analysis:
          analyzer:
            default:
              tokenizer: standard
              filter: [ lowercase, preserved_asciifolding ]

            # This is a special analyzer for autocomplete searches. It's used only
            # in some fields as it can make the index very big.
            autocomplete:
              tokenizer: whitespace
              filter: [ lowercase, engram, preserved_asciifolding ]

            arabic:
              tokenizer: standard
              filter: [ lowercase, arabic_stop, preserved_asciifolding ]
            armenian:
              tokenizer: standard
              filter: [ lowercase, armenian_stop, preserved_asciifolding ]
            basque:
              tokenizer: standard
              filter: [ lowercase, basque_stop, preserved_asciifolding ]
            brazilian:
              tokenizer: standard
              filter: [ lowercase, brazilian_stop, preserved_asciifolding ]
            bulgarian:
              tokenizer: standard
              filter: [ lowercase, bulgarian_stop, preserved_asciifolding ]
            catalan:
              tokenizer: standard
              filter: [ lowercase, catalan_stop, preserved_asciifolding ]
            czech:
              tokenizer: standard
              filter: [ lowercase, czech_stop, preserved_asciifolding ]
            danish:
              tokenizer: standard
              filter: [ lowercase, danish_stop, preserved_asciifolding ]
            dutch:
              tokenizer: standard
              filter: [ lowercase, dutch_stop, preserved_asciifolding ]
            english:
              tokenizer: standard
              filter: [ lowercase, english_stop, preserved_asciifolding ]
            finnish:
              tokenizer: standard
              filter: [ lowercase, finnish_stop, preserved_asciifolding ]
            french:
              tokenizer: standard
              filter: [ lowercase, french_stop, preserved_asciifolding, french_elision ]
            galician:
              tokenizer: standard
              filter: [ lowercase, galician_stop, preserved_asciifolding ]
            german:
              tokenizer: standard
              filter: [ lowercase, german_stop, preserved_asciifolding ]
            greek:
              tokenizer: standard
              filter: [ lowercase, greek_stop, preserved_asciifolding ]
            hindi:
              tokenizer: standard
              filter: [ lowercase, hindi_stop, preserved_asciifolding ]
            hungarian:
              tokenizer: standard
              filter: [ lowercase, hungarian_stop, preserved_asciifolding ]
            indonesian:
              tokenizer: standard
              filter: [ lowercase, indonesian_stop, preserved_asciifolding ]
            italian:
              tokenizer: standard
              filter: [ lowercase, italian_stop, preserved_asciifolding ]
            norwegian:
              tokenizer: standard
              filter: [ lowercase, norwegian_stop, preserved_asciifolding ]
            persian:
              tokenizer: standard
              filter: [ lowercase, persian_stop, preserved_asciifolding ]
            portuguese:
              tokenizer: standard
              filter: [ lowercase, portuguese_stop, preserved_asciifolding ]
            romanian:
              tokenizer: standard
              filter: [ lowercase, romanian_stop, preserved_asciifolding ]
            russian:
              tokenizer: standard
              filter: [ lowercase, russian_stop, preserved_asciifolding ]
            spanish:
              tokenizer: standard
              filter: [ lowercase, spanish_stop, preserved_asciifolding ]
            swedish:
              tokenizer: standard
              filter: [ lowercase, swedish_stop, preserved_asciifolding ]
            turkish:
              tokenizer: standard
              filter: [ lowercase, turkish_stop, preserved_asciifolding ]

          normalizer:
            # Custom normalizer that lowercases text, removes punctation, and
            # does ascii folding for more natural alphabetic sorting
            alphasort:
              type: custom
              filter: [ lowercase, asciifolding ]
              char_filter: [ punctuation_filter ]

          filter:
            engram:
              type: edge_ngram
              min_gram: 3
              max_gram: 10
            french_elision:
              type: elision
              articles: [ l, m, t, qu, n, s, j, d, c, jusqu, quoiqu, lorsqu, puisqu ]
            preserved_asciifolding:
              type: asciifolding
              preserve_original: true

            # To make 'stopwords' works with other token filters the analyzers can't have
            # standard type and the 'stopwords' needs to be added as a token filter too
            arabic_stop:
              type: stop
              stopwords: _arabic_
            armenian_stop:
              type: stop
              stopwords: _armenian_
            basque_stop:
              type: stop
              stopwords: _basque_
            brazilian_stop:
              type: stop
              stopwords: _brazilian_
            bulgarian_stop:
              type: stop
              stopwords: _bulgarian_
            catalan_stop:
              type: stop
              stopwords: _catalan_
            czech_stop:
              type: stop
              stopwords: _czech_
            danish_stop:
              type: stop
              stopwords: _danish_
            dutch_stop:
              type: stop
              stopwords: _dutch_
            english_stop:
              type: stop
              stopwords: _english_
            finnish_stop:
              type: stop
              stopwords: _finnish_
            french_stop:
              type: stop
              stopwords: _french_
            galician_stop:
              type: stop
              stopwords: _galician_
            german_stop:
              type: stop
              stopwords: _german_
            greek_stop:
              type: stop
              stopwords: _greek_
            hindi_stop:
              type: stop
              stopwords: _hindi_
            hungarian_stop:
              type: stop
              stopwords: _hungarian_
            indonesian_stop:
              type: stop
              stopwords: _indonesian_
            italian_stop:
              type: stop
              stopwords: _italian_
            norwegian_stop:
              type: stop
              stopwords: _norwegian_
            persian_stop:
              type: stop
              stopwords: _persian_
            portuguese_stop:
              type: stop
              stopwords: _portuguese_
            romanian_stop:
              type: stop
              stopwords: _romanian_
            russian_stop:
              type: stop
              stopwords: _russian_
            spanish_stop:
              type: stop
              stopwords: _spanish_
            swedish_stop:
              type: stop
              stopwords: _swedish_
            turkish_stop:
              type: stop
              stopwords: _turkish_

          char_filter:

            # This char_filter is added to all analyzers when the index
            # is created in arElasticSearchPlugin initialize when the
            # app_markdown_enabled setting is set to true. Ideally, the
            # Markdown tags should be removed with several regex like
            # in this example: https://github.com/stiang/remove-markdown.
            # But processing all those regex could run very slowly, so
            # we're replacing the following punctuation chars by spaces:
            #     *_#![]()->`+\~:|^=
            strip_md:
              type: pattern_replace
              pattern: '[\*_#!\[\]\(\)\->`\+\\~:\|\^=]'
              replacement: ' '

            # Strip punctation from a string
            punctuation_filter:
              type: pattern_replace
              pattern: '["''_\-\?!\.\(\)\[\]#\*`:;]'
              replacement: ''
EOT;

@unlink(_ATOM_DIR.'/config/search.yml');
file_put_contents(_ATOM_DIR.'/config/search.yml', $search_yml);

//
// php ini
//

$php_ini = <<<EOT
[PHP]
output_buffering = 4096
expose_php = off
log_errors = on
error_reporting = E_ALL
display_errors = /proc/self/fd/2
display_startup_errors = on
max_execution_time = {$CONFIG['php.max_execution_time']}
max_input_time = {$CONFIG['php.max_input_time']}
memory_limit = {$CONFIG['php.memory_limit']}
log_errors = on
post_max_size = {$CONFIG['php.post_max_size']}
default_charset = UTF-8
cgi.fix_pathinfo = off
upload_max_filesize = {$CONFIG['php.upload_max_filesize']}
max_file_uploads = {$CONFIG['php.max_file_uploads']}
date.timezone = {$CONFIG['php.date.timezone']}
session.use_only_cookies = off
opcache.fast_shutdown = on
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = off
pcov.enabled = 0
EOT;

@unlink(_ETC_DIR.'/php/php.ini');
file_put_contents(_ETC_DIR.'/php/php.ini', $php_ini);

//
// fpm ini
//

$fpm_ini = <<<'EOT'
[global]
error_log = /proc/self/fd/2
log_level = notice
daemonize = yes

[atom]
; The user running the application
user = atom
group = atom

listen = /run/php-fpm/atom.sock
listen.owner = atom
listen.group = atom

; The following directives should be tweaked based in your hardware resources
pm = dynamic
pm.max_children = 30
pm.start_servers = 10
pm.min_spare_servers = 10
pm.max_spare_servers = 10
pm.max_requests = 200

; APC
php_admin_value[apc.enabled] = 1
php_admin_value[apc.shm_size] = 192M
php_admin_value[apc.num_files_hint] = 5000
php_admin_value[apc.stat] = 0

; Zend OPcache
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.enable_cli] = 0
php_admin_value[opcache.memory_consumption] = 192
php_admin_value[opcache.interned_strings_buffer] = 16
php_admin_value[opcache.max_accelerated_files] = 4000
php_admin_value[opcache.fast_shutdown] = 1
php_admin_value[opcache.validate_timestamps] = 0

; The following directives are recommended to be set when using php-fpm with docker
access.log = /proc/self/fd/2
clear_env = no
catch_workers_output = yes
EOT;

@unlink(_ETC_DIR.'/php-fpm.d/atom.conf');
file_put_contents(_ETC_DIR.'/php-fpm.d/atom.conf', $fpm_ini);

//
// sf symlink
//

@symlink(_ATOM_DIR.'/vendor/symfony/data/web/sf', _ATOM_DIR.'/sf');