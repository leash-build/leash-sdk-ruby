# frozen_string_literal: true

require_relative "base"

module Leash
  module Integrations
    # `leash.integrations.linear` — mirrors TS `leash.integrations.linear`.
    #
    # The Linear MCP uses underscored action names on the wire (`list_issues`,
    # `get_issue`, …) — preserved here. List responses can come back as either
    # a bare array or an envelope hash; the SDK tolerates both shapes.
    class Linear < Base
      PROVIDER = "linear"

      def list_issues(team_id: nil, assignee_id: nil, state_type: nil,
                      limit: nil, cursor: nil)
        params = compact_params(
          "teamId" => team_id,
          "assigneeId" => assignee_id,
          "stateType" => state_type,
          "limit" => limit,
          "cursor" => cursor
        )

        raw = call("list_issues", params)
        case raw
        when Array
          { "issues" => raw }
        when Hash
          out = { "issues" => raw["issues"] || [] }
          out["cursor"] = raw["cursor"] if raw["cursor"]
          out
        else
          { "issues" => [] }
        end
      end

      def get_issue(id)
        call("get_issue", { "id" => id })
      end

      def create_issue(team_id:, title:, description: nil, assignee_id: nil,
                       priority: nil, label_ids: nil)
        params = { "teamId" => team_id, "title" => title }
        params["description"] = description unless description.nil?
        params["assigneeId"] = assignee_id unless assignee_id.nil?
        params["priority"] = priority unless priority.nil?
        params["labelIds"] = label_ids unless label_ids.nil?
        call("create_issue", params)
      end

      def update_issue(id, title: nil, description: nil, assignee_id: nil,
                       priority: nil, label_ids: nil, team_id: nil)
        params = { "id" => id }
        params["title"] = title unless title.nil?
        params["description"] = description unless description.nil?
        params["assigneeId"] = assignee_id unless assignee_id.nil?
        params["priority"] = priority unless priority.nil?
        params["labelIds"] = label_ids unless label_ids.nil?
        params["teamId"] = team_id unless team_id.nil?
        call("update_issue", params)
      end

      def add_comment(issue_id, body)
        call("add_comment", { "issueId" => issue_id, "body" => body })
      end

      def list_teams
        raw = call("list_teams", {})
        case raw
        when Array then raw
        when Hash  then raw["teams"] || []
        else            []
        end
      end

      def list_projects(team_id: nil)
        params = compact_params("teamId" => team_id)
        raw = call("list_projects", params)
        case raw
        when Array then raw
        when Hash  then raw["projects"] || []
        else            []
        end
      end
    end
  end
end
