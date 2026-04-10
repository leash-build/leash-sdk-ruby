# frozen_string_literal: true

module Leash
  # Client for Google Drive operations via the Leash platform proxy.
  #
  # Not instantiated directly -- use {Integrations#drive} instead.
  class DriveClient
    PROVIDER = "google_drive"

    # @api private
    def initialize(call_fn)
      @call = call_fn
    end

    # List files in the user's Drive.
    #
    # @param query [String, nil] Drive search query (Google Drive API query syntax)
    # @param max_results [Integer, nil] maximum number of files to return
    # @param folder_id [String, nil] restrict to files within a specific folder
    # @return [Hash] hash with "files" list
    def list_files(query: nil, max_results: nil, folder_id: nil)
      params = {}
      params["query"] = query if query
      params["maxResults"] = max_results if max_results
      params["folderId"] = folder_id if folder_id
      @call.call(PROVIDER, "list-files", params)
    end

    # Get file metadata by ID.
    #
    # @param file_id [String] the file identifier
    # @return [Hash] the file metadata object
    def get_file(file_id)
      @call.call(PROVIDER, "get-file", { "fileId" => file_id })
    end

    # Search files using a query string.
    #
    # @param query [String] search query (Google Drive API query syntax)
    # @param max_results [Integer, nil] maximum number of results
    # @return [Hash] hash with "files" list
    def search_files(query, max_results: nil)
      params = { "query" => query }
      params["maxResults"] = max_results if max_results
      @call.call(PROVIDER, "search-files", params)
    end
  end
end
