# frozen_string_literal: true

require_relative "test_helper"

class TestIntegrationsLinear < Minitest::Test
  def setup
    @client, @runner = build_client(
      canned: FakeResponse.new(200, '{"success":true,"data":{"issues":[{"id":"i-1"}],"cursor":"abc"}}')
    )
  end

  def test_list_issues_url
    @client.integrations.linear.list_issues(state_type: "started")
    assert_equal "/api/integrations/linear/list_issues", @runner.uri.path
    assert_equal({ "stateType" => "started" }, @runner.request_body)
  end

  def test_list_issues_returns_envelope
    result = @client.integrations.linear.list_issues
    assert_equal [{ "id" => "i-1" }], result["issues"]
    assert_equal "abc", result["cursor"]
  end

  def test_list_issues_tolerates_bare_array
    client, _ = build_client(canned: FakeResponse.new(200, '[{"id":"i-2"}]'))
    result = client.integrations.linear.list_issues
    assert_equal [{ "id" => "i-2" }], result["issues"]
    refute result.key?("cursor")
  end

  def test_list_issues_with_full_filter
    @client.integrations.linear.list_issues(
      team_id: "t-1", assignee_id: "u-1", state_type: "started", limit: 50, cursor: "c"
    )
    body = @runner.request_body
    assert_equal "t-1", body["teamId"]
    assert_equal "u-1", body["assigneeId"]
    assert_equal "started", body["stateType"]
    assert_equal 50, body["limit"]
    assert_equal "c", body["cursor"]
  end

  def test_get_issue
    client, runner = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"id":"i-1","title":"x"}}'))
    issue = client.integrations.linear.get_issue("i-1")
    assert_equal "/api/integrations/linear/get_issue", runner.uri.path
    assert_equal({ "id" => "i-1" }, runner.request_body)
    assert_equal "x", issue["title"]
  end

  def test_create_issue
    client, runner = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"id":"i-9"}}'))
    client.integrations.linear.create_issue(
      team_id: "t-1", title: "Build it",
      description: "desc", assignee_id: "u-1", priority: 2, label_ids: ["L1"]
    )
    assert_equal "/api/integrations/linear/create_issue", runner.uri.path
    body = runner.request_body
    assert_equal "t-1", body["teamId"]
    assert_equal "Build it", body["title"]
    assert_equal "desc", body["description"]
    assert_equal "u-1", body["assigneeId"]
    assert_equal 2, body["priority"]
    assert_equal ["L1"], body["labelIds"]
  end

  def test_update_issue
    client, runner = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"id":"i-1"}}'))
    client.integrations.linear.update_issue("i-1", title: "new", priority: 1)
    assert_equal "/api/integrations/linear/update_issue", runner.uri.path
    body = runner.request_body
    assert_equal "i-1", body["id"]
    assert_equal "new", body["title"]
    assert_equal 1, body["priority"]
  end

  def test_add_comment
    client, runner = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"id":"c-1"}}'))
    client.integrations.linear.add_comment("i-1", "hello")
    assert_equal "/api/integrations/linear/add_comment", runner.uri.path
    assert_equal({ "issueId" => "i-1", "body" => "hello" }, runner.request_body)
  end

  def test_list_teams_returns_array_from_envelope
    client, _ = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"teams":[{"id":"t-1","key":"LEA","name":"Leash"}]}}'))
    teams = client.integrations.linear.list_teams
    assert_equal 1, teams.length
    assert_equal "LEA", teams.first["key"]
  end

  def test_list_teams_returns_array_from_bare
    client, _ = build_client(canned: FakeResponse.new(200, '[{"id":"t-1","key":"LEA","name":"Leash"}]'))
    teams = client.integrations.linear.list_teams
    assert_equal "LEA", teams.first["key"]
  end

  def test_list_projects_returns_array
    client, runner = build_client(canned: FakeResponse.new(200, '{"success":true,"data":{"projects":[{"id":"p-1","name":"P"}]}}'))
    projects = client.integrations.linear.list_projects(team_id: "t-1")
    assert_equal "/api/integrations/linear/list_projects", runner.uri.path
    assert_equal({ "teamId" => "t-1" }, runner.request_body)
    assert_equal "P", projects.first["name"]
  end

  def test_seven_verbs_exposed
    verbs = %i[list_issues get_issue create_issue update_issue add_comment list_teams list_projects]
    verbs.each { |v| assert @client.integrations.linear.respond_to?(v), "missing verb #{v}" }
    assert_equal 7, verbs.length
  end

  def test_linear_propagates_401
    client, _ = build_client(canned: FakeResponse.new(401, '{"error":"no"}'))
    assert_raises(Leash::UnauthorizedError) { client.integrations.linear.list_teams }
  end

  def test_linear_propagates_402
    client, _ = build_client(canned: FakeResponse.new(402, '{"message":"upgrade"}'))
    assert_raises(Leash::UpgradeRequiredError) { client.integrations.linear.list_teams }
  end

  def test_linear_propagates_404
    client, _ = build_client(canned: FakeResponse.new(404, '{"error":"nope"}'))
    assert_raises(Leash::Error) { client.integrations.linear.list_teams }
  end

  def test_linear_propagates_500
    client, _ = build_client(canned: FakeResponse.new(500, '{"error":"server broke"}'))
    assert_raises(Leash::Error) { client.integrations.linear.list_teams }
  end
end
