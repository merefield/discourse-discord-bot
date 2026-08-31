# frozen_string_literal: true

describe DiscordBot::Utils do
  fab!(:user)
  fab!(:proxy_user, :user)

  fab!(:associated_account) do
    Fabricate(
      :user_associated_account,
      user: user,
      provider_name: "discord",
      provider_uid: "123456789012345678",
    )
  end

  describe ".convert_mentions" do
    it "converts linked Discord mention formats" do
      text = "Hello <@123456789012345678> and <@!123456789012345678>"

      expect(described_class.convert_mentions(text)).to eq(
        "Hello @#{user.username} and @#{user.username}",
      )
    end

    it "preserves unresolved Discord mentions" do
      text = "Hello <@987654321098765432>"

      expect(described_class.convert_mentions(text)).to eq(text)
    end
  end

  describe ".prepare_posts" do
    it "loads linked users once for a batch of messages" do
      author = stub(id: associated_account.provider_uid)
      messages =
        Array.new(2) do
          stub(
            author: author,
            attachments: [],
            embeds: [],
            to_s: "Hello <@#{associated_account.provider_uid}>",
          )
        end

      queries = track_sql_queries { @prepared_posts = described_class.prepare_posts(messages) }

      expect(@prepared_posts).to all(eq([user, "Hello @#{user.username}"]))
      expect(queries.count { |query| query.include?("user_associated_accounts") }).to eq(1)
    end

    it "uses the configured proxy for unlinked authors" do
      SiteSetting.discord_bot_unknown_user_proxy_account = proxy_user.username
      message = stub(author: stub(id: "987"), attachments: [], embeds: [], to_s: "Hello")

      expect(described_class.prepare_posts([message])).to eq([[proxy_user, "Hello"]])
    end
  end
end
