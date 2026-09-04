# frozen_string_literal: true

describe DiscordBot::BotCommands do
  describe ".manage_discord_commands" do
    before { DiscordBot::DiscordrbLoader.load }

    def build_command_bot(event, arguments)
      Class
        .new do
          attr_reader :token

          def initialize(event, arguments)
            @event = event
            @arguments = arguments
            @token = "Bot MTIz.signature"
          end

          def bucket(*)
          end

          def command(name, **)
            yield(@event, *@arguments) if name == :disccopy
          end

          def message(**)
          end
        end
        .new(event, arguments)
    end

    it "reports an error without a success link when no history is available" do
      channel = stub(type: Discordrb::Channel::TYPES.fetch(:text))
      channel.expects(:history).with(10, 123).returns([])
      message = stub(id: 123, channel: stub(name: "general"))
      event = stub(bot: Object.new, channel: channel, message: message)
      event
        .expects(:respond)
        .once
        .with(I18n.t("discord_bot.commands.disccopy.error.no_messages_found"))

      DiscordBot::Manager.stubs(:with_bot_connection).yields

      described_class.manage_discord_commands(build_command_bot(event, ["10", nil, nil]))
    end

    it "appends an untargeted history copy to the automatic-sync topic" do
      SiteSetting.discord_bot_auto_channel_sync = true
      category = Fabricate(:category, name: "discord-history")
      topic =
        Fabricate(
          :topic,
          category: category,
          title:
            I18n.t(
              "discord_bot.discord_events.auto_message_copy.default_topic_title",
              channel_name: category.name,
            ),
        )
      author = stub(id: 456)
      history_message =
        stub(
          id: 122,
          content: "Earlier message",
          author: author,
          embeds: [],
          attachments: [],
          link: "https://discord.example/message/122",
          to_s: "Earlier message",
        )
      channel =
        stub(
          type: Discordrb::Channel::TYPES.fetch(:text),
          name: category.name,
          history: [history_message],
        )
      command_message = stub(id: 123, channel: channel)
      event = stub(bot: Object.new, channel: channel, message: command_message)
      event.stubs(:respond)
      DiscordBot::Manager.stubs(:with_bot_connection).yields
      original_topic_count = Topic.count

      expect do
        described_class.manage_discord_commands(build_command_bot(event, ["1", nil, nil]))
      end.to change { topic.posts.count }.by(1)

      expect(Topic.count).to eq(original_topic_count)
      expect(topic.posts.order(:post_number).last.raw).to eq("Earlier message")
    end

    it "creates one automatic-sync topic for a multi-batch history copy" do
      SiteSetting.discord_bot_auto_channel_sync = true
      SiteSetting.discord_bot_message_copy_topic_size_limit = 1
      category = Fabricate(:category, name: "discord-backfill")
      author = stub(id: 456)
      history_messages =
        [122, 121].map do |message_id|
          stub(
            id: message_id,
            content: "Message #{message_id}",
            author: author,
            embeds: [],
            attachments: [],
            link: "https://discord.example/message/#{message_id}",
            to_s: "Message #{message_id}",
          )
        end
      channel =
        stub(
          type: Discordrb::Channel::TYPES.fetch(:text),
          name: category.name,
          history: history_messages,
        )
      command_message = stub(id: 123, channel: channel)
      event = stub(bot: Object.new, channel: channel, message: command_message)
      event.stubs(:respond)
      DiscordBot::Manager.stubs(:with_bot_connection).yields
      automatic_topic_title =
        I18n.t(
          "discord_bot.discord_events.auto_message_copy.default_topic_title",
          channel_name: category.name,
        )

      expect do
        described_class.manage_discord_commands(build_command_bot(event, ["2", nil, nil]))
      end.to change { Topic.where(title: automatic_topic_title, category: category).count }.by(1)

      expect(Topic.find_by!(title: automatic_topic_title, category: category).posts.count).to eq(2)
    end

    it "creates a history topic when automatic channel sync is disabled" do
      SiteSetting.discord_bot_auto_channel_sync = false
      category = Fabricate(:category, name: "discord-archive")
      author = stub(id: 456)
      history_message =
        stub(
          id: 122,
          content: "Archived message",
          author: author,
          embeds: [],
          attachments: [],
          link: "https://discord.example/message/122",
          to_s: "Archived message",
        )
      channel =
        stub(
          type: Discordrb::Channel::TYPES.fetch(:text),
          name: category.name,
          history: [history_message],
        )
      command_message = stub(id: 123, channel: channel)
      event = stub(bot: Object.new, channel: channel, message: command_message)
      event.stubs(:respond)
      DiscordBot::Manager.stubs(:with_bot_connection).yields
      history_topic_title =
        I18n.t("discord_bot.commands.disccopy.discourse_topic_title", channel: category.name)

      expect do
        described_class.manage_discord_commands(build_command_bot(event, ["1", nil, nil]))
      end.to change { Topic.where(title: history_topic_title, category: category).count }.by(1)
    end
  end

  describe ".discord_users_below_trust_level" do
    fab!(:low_trust_user) { Fabricate(:user, trust_level: 1) }
    fab!(:trusted_user) { Fabricate(:user, trust_level: 3) }
    fab!(:low_trust_account) do
      Fabricate(
        :user_associated_account,
        user: low_trust_user,
        provider_name: "discord",
        provider_uid: "low-trust",
      )
    end
    fab!(:trusted_account) do
      Fabricate(
        :user_associated_account,
        user: trusted_user,
        provider_name: "discord",
        provider_uid: "trusted",
      )
    end

    it "loads linked users below the threshold in one query" do
      queries = track_sql_queries { @user_ids = described_class.discord_users_below_trust_level(2) }

      expect(@user_ids).to eq([low_trust_account.provider_uid])
      expect(queries.count { |query| query.include?("user_associated_accounts") }).to eq(1)
    end
  end

  describe ".group_sync_data" do
    fab!(:user)
    fab!(:associated_account) do
      Fabricate(
        :user_associated_account,
        user: user,
        provider_name: "discord",
        provider_uid: "group-member",
      )
    end
    fab!(:group) { Fabricate(:group, visibility_level: 0) }
    fab!(:group_user) { Fabricate(:group_user, group: group, user: user) }

    it "loads eligible linked memberships without per-user queries" do
      queries =
        track_sql_queries do
          @group_count, @memberships =
            described_class.group_sync_data(0, include_automated_groups: false)
        end

      expect(@group_count).to be >= 1
      expect(@memberships).to contain_exactly(
        {
          discourse_username: user.username,
          discord_uid: associated_account.provider_uid,
          discourse_group_id: group.id,
          discourse_group_name: group.name,
        },
      )
      expect(queries.count { |query| query.include?("user_associated_accounts") }).to eq(1)
      expect(queries.count { |query| query.match?(/COUNT.*groups/m) }).to eq(1)
    end
  end

  describe ".fetch_history" do
    it "accumulates paginated history up to the requested count" do
      requests = []
      next_id = 300
      message_class = Struct.new(:id)
      channel = Object.new
      channel.define_singleton_method(:history) do |count, before_id|
        requests << [count, before_id]
        Array.new(count) { message_class.new(next_id -= 1) }
      end

      messages = described_class.fetch_history(channel, 500, 250)

      expect(messages.size).to eq(250)
      expect(requests).to eq([[100, 500], [100, 200], [50, 100]])
    end

    it "stops requesting pages after reaching the start of history" do
      channel = mock
      channel.expects(:history).with(100, 500).returns([stub(id: 499)])

      expect(described_class.fetch_history(channel, 500, 200).size).to eq(1)
    end
  end

  describe ".default_history_count" do
    it "caps the thread default at the configured maximum" do
      SiteSetting.discord_bot_message_copy_max_messages = 20

      expect(described_class.default_history_count).to eq(20)
    end
  end

  it "bounds the configured message limit" do
    expect { SiteSetting.discord_bot_message_copy_max_messages = 10_001 }.to raise_error(
      Discourse::InvalidParameters,
    )
  end
end
