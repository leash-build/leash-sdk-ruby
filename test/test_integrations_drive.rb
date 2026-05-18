# frozen_string_literal: true

require_relative "test_helper"

class TestIntegrationsDrive < Minitest::Test
  def setup
    @client, @runner = build_client
  end

  def test_list_files
    @client.integrations.drive.list_files(query: "name contains 'q'", max_results: 10, folder_id: "fold-1")
    assert_equal "/api/integrations/google_drive/list-files", @runner.uri.path
    assert_equal({ "query" => "name contains 'q'", "maxResults" => 10, "folderId" => "fold-1" }, @runner.request_body)
  end

  def test_list_files_no_args
    @client.integrations.drive.list_files
    assert_equal "/api/integrations/google_drive/list-files", @runner.uri.path
    assert_equal({}, @runner.request_body || {})
  end

  def test_get_file
    @client.integrations.drive.get_file("file-42")
    assert_equal "/api/integrations/google_drive/get-file", @runner.uri.path
    assert_equal({ "fileId" => "file-42" }, @runner.request_body)
  end

  def test_download_file
    @client.integrations.drive.download_file("file-42")
    assert_equal "/api/integrations/google_drive/download-file", @runner.uri.path
    assert_equal({ "fileId" => "file-42" }, @runner.request_body)
  end

  def test_create_folder
    @client.integrations.drive.create_folder("Receipts")
    assert_equal "/api/integrations/google_drive/create-folder", @runner.uri.path
    assert_equal({ "name" => "Receipts" }, @runner.request_body)
  end

  def test_create_folder_with_parent
    @client.integrations.drive.create_folder("Receipts", parent_id: "p-1")
    assert_equal({ "name" => "Receipts", "parentId" => "p-1" }, @runner.request_body)
  end

  def test_upload_file
    @client.integrations.drive.upload_file(name: "n.txt", content: "data", mime_type: "text/plain")
    assert_equal "/api/integrations/google_drive/upload-file", @runner.uri.path
    body = @runner.request_body
    assert_equal "n.txt", body["name"]
    assert_equal "data", body["content"]
    assert_equal "text/plain", body["mimeType"]
  end

  def test_upload_file_with_parent
    @client.integrations.drive.upload_file(name: "n.txt", content: "data", mime_type: "text/plain", parent_id: "p")
    assert_equal "p", @runner.request_body["parentId"]
  end

  def test_delete_file
    @client.integrations.drive.delete_file("file-42")
    assert_equal "/api/integrations/google_drive/delete-file", @runner.uri.path
    assert_equal({ "fileId" => "file-42" }, @runner.request_body)
  end

  def test_search_files
    @client.integrations.drive.search_files("invoice", max_results: 7)
    assert_equal "/api/integrations/google_drive/search-files", @runner.uri.path
    assert_equal({ "query" => "invoice", "maxResults" => 7 }, @runner.request_body)
  end

  def test_seven_verbs_exposed
    verbs = %i[list_files get_file download_file create_folder upload_file delete_file search_files]
    verbs.each { |v| assert @client.integrations.drive.respond_to?(v), "missing verb #{v}" }
    assert_equal 7, verbs.length
  end

  def test_drive_propagates_401
    client, _ = build_client(canned: FakeResponse.new(401, '{"error":"no"}'))
    assert_raises(Leash::UnauthorizedError) { client.integrations.drive.list_files }
  end

  def test_drive_propagates_402
    client, _ = build_client(canned: FakeResponse.new(402, '{"message":"upgrade"}'))
    assert_raises(Leash::UpgradeRequiredError) { client.integrations.drive.list_files }
  end

  def test_drive_propagates_404
    client, _ = build_client(canned: FakeResponse.new(404, '{"error":"nope"}'))
    assert_raises(Leash::Error) { client.integrations.drive.list_files }
  end

  def test_drive_propagates_500
    client, _ = build_client(canned: FakeResponse.new(500, '{"error":"server broke"}'))
    assert_raises(Leash::Error) { client.integrations.drive.list_files }
  end
end
