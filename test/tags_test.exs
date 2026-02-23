# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.TagsTest do
  use ExUnit.Case, async: false

  use AshOban.Test, repo: AshOban.Test.Repo, prefix: "private"

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.TagsTest.TaggedResource
    end
  end

  defmodule TaggedResource do
    use Ash.Resource,
      domain: AshOban.TagsTest.TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        trigger :tagged do
          action :process
          where expr(processed != true)
          scheduler_cron false
          queue :triggered_tags_tagged
          tags(["trigger-tag"])
          worker_module_name AshOban.TagsTest.TaggedResource.Worker.Tagged
          scheduler_module_name AshOban.TagsTest.TaggedResource.Scheduler.Tagged
        end

        trigger :merged_tags do
          action :process
          where expr(processed != true)
          scheduler_cron false
          queue :triggered_tags_merged_tags
          tags(["base-tag"])
          worker_opts tags: ["extra-tag"]
          worker_module_name AshOban.TagsTest.TaggedResource.Worker.MergedTags
          scheduler_module_name AshOban.TagsTest.TaggedResource.Scheduler.MergedTags
        end
      end

      scheduled_actions do
        schedule :tagged_action, "0 0 1 1 *" do
          action :say_hello
          queue :triggered_tags_tagged_action
          tags(["schedule-tag"])
          worker_module_name AshOban.TagsTest.TaggedResource.ActionWorker.TaggedAction
        end
      end
    end

    actions do
      defaults create: []

      read :read do
        primary? true
        pagination keyset?: true
      end

      update :process do
        change set_attribute(:processed, true)
      end

      action :say_hello, :string do
        run fn _, _ -> {:ok, "hello"} end
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :processed, :boolean, default: false, allow_nil?: false, public?: true
      timestamps()
    end
  end

  setup_all do
    AshOban.Test.Repo.start_link()
    Oban.start_link(AshOban.config([TestDomain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup do
    Oban.delete_all_jobs(Oban.Job)
    :ok
  end

  test "tags are set on trigger worker jobs" do
    record =
      TaggedResource
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    AshOban.Test.assert_would_schedule(record, :tagged)

    AshOban.run_trigger(record, :tagged)

    [job] = assert_triggered(record, :tagged)
    assert job.tags == ["trigger-tag"]
  end

  test "tags from the DSL option are merged with tags in worker_opts" do
    record =
      TaggedResource
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    AshOban.Test.assert_would_schedule(record, :merged_tags)

    AshOban.run_trigger(record, :merged_tags)

    [job] = assert_triggered(record, :merged_tags)
    assert "base-tag" in job.tags
    assert "extra-tag" in job.tags
  end

  test "tags are set on scheduled action jobs" do
    AshOban.schedule(TaggedResource, :tagged_action)

    assert [job] =
             all_enqueued(worker: AshOban.TagsTest.TaggedResource.ActionWorker.TaggedAction)

    assert job.tags == ["schedule-tag"]
  end
end
