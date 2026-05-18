# frozen_string_literal: true

require_relative "base"

module Leash
  module Integrations
    # `leash.integrations.drive` — mirrors TS `leash.integrations.drive`.
    # Wire provider id is `google_drive` (also aliased as
    # `leash.integrations.google_drive`).
    class Drive < Base
      PROVIDER = "google_drive"

      def list_files(query: nil, max_results: nil, folder_id: nil)
        params = compact_params(
          "query" => query,
          "maxResults" => max_results,
          "folderId" => folder_id
        )
        call("list-files", params.empty? ? nil : params)
      end

      def get_file(file_id)
        call("get-file", { "fileId" => file_id })
      end

      def download_file(file_id)
        call("download-file", { "fileId" => file_id })
      end

      def create_folder(name, parent_id: nil)
        params = { "name" => name }
        params["parentId"] = parent_id unless parent_id.nil?
        call("create-folder", params)
      end

      def upload_file(name:, content:, mime_type:, parent_id: nil)
        params = { "name" => name, "content" => content, "mimeType" => mime_type }
        params["parentId"] = parent_id unless parent_id.nil?
        call("upload-file", params)
      end

      def delete_file(file_id)
        call("delete-file", { "fileId" => file_id })
      end

      def search_files(query, max_results: nil)
        params = { "query" => query }
        params["maxResults"] = max_results unless max_results.nil?
        call("search-files", params)
      end
    end
  end
end
