# frozen_string_literal: true

module ::DiscordBot::Utils
  include ActionView::Helpers::DateHelper

  module_function

  def prepare_post(pm)
    raw = pm.to_s
    embed = pm.embeds[0]

    # embed
    if raw.present?
      raw = convert_timestamps(raw)
      raw = format_youtube_links(raw)
      #mentions
      if SiteSetting.discord_bot_message_copy_convert_discord_mentions_to_usernames
        raw = convert_mentions(raw)
      end
    elsif embed.present?
      url = embed.url
      thumbnail_url = embed.thumbnail&.url || embed.image&.url || embed.video&.url || ""
      description = embed.description
      title = embed.title
      raw =
        I18n.t(
          "discord_bot.discord_events.auto_message_copy.embed",
          url: url,
          description: description,
          title: title,
          thumbnail_url: thumbnail_url,
        )
    end

    # attachments
    pm.attachments.each do |attachment|
      if attachment.content_type.include?("image")
        raw = raw.present? ? raw + "\n\n" + attachment.url : attachment.url
      else
        raw =
          (
            if raw.present?
              raw + "\n\n<a href='#{attachment.url}'>#{attachment.filename}</a>"
            else
              "<a href='#{attachment.url}'>#{attachment.filename}</a>"
            end
          )
      end
    end

    # associated author
    associated_user =
      UserAssociatedAccount.find_by(provider_uid: pm.author.id, provider_name: "discord")
    proxy_account = User.find_by(name: SiteSetting.discord_bot_unknown_user_proxy_account)

    if associated_user.nil?
      posting_user = proxy_account.nil? ? system_user : proxy_account
    else
      posting_user = User.find_by(id: associated_user.user_id)
    end

    [posting_user, raw]
  end

  def convert_timestamps(text)
    # Define a hash mapping format types to strftime patterns
    format_map = {
      "t" => "%-I:%M %p", # Short time, e.g., "6:00 PM"
      "T" => "%-I:%M:%S %p", # Long time, e.g., "6:00:00 PM"
      "d" => "%m/%d/%Y", # Short date, e.g., "02/10/2024"
      "D" => "%B %-d, %Y", # Long date, e.g., "October 2, 2024"
      "f" => "%B %-d, %Y %-I:%M %p", # Long date and short time, e.g., "October 2, 2024 6:00 PM"
      "F" => "%A, %B %-d, %Y %-I:%M %p", # Full date and time, e.g., "Wednesday, October 2, 2024 6:00 PM"
    }

    # Regular expression to match the pattern <t:UNIX_TIMESTAMP:FORMAT>
    text.gsub(/<t:(\d+):([tTdDfFR])>/) do |match|
      # Extract the timestamp and the format type
      timestamp = $1.to_i
      format_type = $2
      time = Time.at(timestamp)

      # Check if it's a relative time ('R') format
      if format_type == "R"
        # Get the relative time and check if it's in the future or past
        relative_time = time_ago_in_words(time)
        if time > Time.now
          "in #{relative_time}"
        else
          "#{relative_time} ago"
        end
      else
        # Convert the timestamp to Time and format it according to the specified format type
        time.strftime(format_map[format_type])
      end
    end
  end

  def convert_mentions(text)
    text.gsub(/<@!?(\d+)>/) do |mention|
      provider_uid = Regexp.last_match(1)
      associated_user =
        UserAssociatedAccount.find_by(provider_uid: provider_uid, provider_name: "discord")
      mentioned_user = User.find_by(id: associated_user&.user_id)

      mentioned_user ? "@#{mentioned_user.username}" : mention
    end
  end

  def format_youtube_links(text)
    # Regular expression to match YouTube URLs
    youtube_regex = %r{(https?://(?:www\.)?(?:youtube\.com|youtu\.be)/[^\s]+)}

    # Use gsub to find and format YouTube links with two new lines before and after
    text.gsub(youtube_regex) { |match| "\n\n#{match}\n\n" }
  end
end
