# frozen_string_literal: true

describe DiscordBot::Utils do
  fab!(:user)

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
end
