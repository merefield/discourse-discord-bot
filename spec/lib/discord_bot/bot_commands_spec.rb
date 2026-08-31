# frozen_string_literal: true

describe DiscordBot::BotCommands do
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
