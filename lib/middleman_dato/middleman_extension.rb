# frozen_string_literal: true

require 'middleman-core'
require 'middleman-core/version'
require 'dato/site/client'
require 'dato/local/loader'
require 'dato/utils/seo_tags_builder'
require 'dato/utils/favicon_tags_builder'
require 'dotenv'

module MiddlemanDato
  class MiddlemanExtension < ::Middleman::Extension
    attr_reader :loader

    option :token, ENV['DATO_API_TOKEN'], 'Project API token'
    option :api_base_url, 'https://site-api.datocms.com', 'API Base URL'
    option :live_reload, true, 'Live reload of content coming from DatoCMS'
    option :preview, false, 'Show latest (unpublished) version of your content'
    option :environment, nil, 'Environment to fetch data from'

    option :base_url, nil, 'Website base URL (deprecated)'
    option :domain, nil, 'Site domain (deprecated)'

    expose_to_config dato: :dato_collector
    expose_to_application dato_items_repo: :items_repo

    def initialize(app, options_hash = {}, &block)
      super

      return if app.mode?(:config)

      @loader = loader = Dato::Local::Loader.new(
        client,
        options_hash[:preview]
      )

      loader.load

      app.after_configuration do
        if options_hash[:live_reload] && !app.build?
          loader.watch do
            puts "DatoCMS content changed!"
            app.sitemap.rebuild_resource_list!(:touched_dato_content)
          end
        end
      end
    end

    def client
      token = options[:token]

      if token.blank? && File.exist?('.env')
        token = Dotenv::Environment.new('.env')['DATO_API_TOKEN']
      end

      if token.blank?
        raise RuntimeError, 'Missing DatoCMS site API token!'
      end

      @client ||= Dato::Site::Client.new(
        token,
        base_url: options[:api_base_url],
        environment: options[:environment],
        extra_headers: {
          'X-Reason' => 'dump',
          'X-SSG' => 'middleman'
        }
      )
    end

    def dato_collector
      app.dato_items_repo
    end

    def items_repo
      loader.items_repo
    end

    module InstanceMethods
      def dato
        extensions[:dato].items_repo
      end
    end

    helpers do
      def dato
        extensions[:dato].items_repo
      end

      def dato_meta_tags(item)
        meta_tags = Dato::Utils::SeoTagsBuilder.new(item, dato.site).meta_tags

        meta_tags.map do |data|
          if data[:content]
            content_tag(data[:tag_name], data[:content], data[:attributes])
          else
            tag(data[:tag_name], data[:attributes])
          end
        end.join
      end

      def dato_favicon_meta_tags(options = {})
        meta_tags = Dato::Utils::FaviconTagsBuilder.new(
          dato.site,
          options[:theme_color]
        ).meta_tags

        meta_tags.map do |data|
          if data[:content]
            content_tag(data[:tag_name], data[:content], data[:attributes])
          else
            tag(data[:tag_name], data[:attributes])
          end
        end.join
      end
    end
  end
end
