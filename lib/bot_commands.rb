# frozen_string_literal: true
module ::DiscordBot::BotCommands
  HISTORY_CHUNK_LIMIT = 100

  def self.thread_types
    @thread_types ||=
      %i[news_thread public_thread private_thread].map do |type|
        Discordrb::Channel::TYPES.fetch(type)
      end
  end

  def self.fetch_history(channel, before_id, count)
    messages = []

    while messages.length < count
      batch_size = [count - messages.length, HISTORY_CHUNK_LIMIT].min
      batch = channel.history(batch_size, before_id)
      break if batch.empty?

      messages.concat(batch)
      break if batch.length < batch_size

      before_id = batch.last.id
    end

    messages
  end

  def self.default_history_count
    [HISTORY_CHUNK_LIMIT, SiteSetting.discord_bot_message_copy_max_messages].min
  end

  def self.discord_users_below_trust_level(min_trust_level)
    UserAssociatedAccount
      .joins(:user)
      .where(provider_name: "discord")
      .where("users.trust_level < ?", min_trust_level)
      .pluck(:provider_uid)
  end

  def self.group_sync_data(max_group_visibility, include_automated_groups:)
    groups = Group.where("visibility_level <= ?", max_group_visibility)
    groups = groups.where(automatic: false) unless include_automated_groups

    memberships =
      UserAssociatedAccount
        .joins(user: :groups)
        .merge(groups)
        .where(provider_name: "discord")
        .pluck("users.username", :provider_uid, "groups.id", "groups.name")
        .map do |username, provider_uid, group_id, group_name|
          {
            discourse_username: username,
            discord_uid: provider_uid,
            discourse_group_id: group_id,
            discourse_group_name: group_name,
          }
        end

    [groups.count, memberships]
  end

  def self.manage_discord_commands(bot)
    bot.bucket :admin_tasks, limit: 3, time_span: 60, delay: 10

    # '!disccopy' - a command to copy message history to Topics in Discourse

    bot.command(
      :disccopy,
      min_args: 0,
      max_args: 3,
      bucket: :admin_tasks,
      rate_limit_message: I18n.t("discord_bot.commands.rate_limit_breached"),
      required_roles: [SiteSetting.discord_bot_admin_role_id],
      description: I18n.t("discord_bot.commands.disccopy.description"),
    ) do |event, number_of_past_messages, target_category, target_topic|
      ::DiscordBot::Manager.with_bot_connection(event.bot) do
        thread_channel = thread_types.include?(event.channel.type)
        requested_message_count = Integer(number_of_past_messages, exception: false)

        if number_of_past_messages.blank?
          if !thread_channel
            event.respond I18n.t("discord_bot.commands.disccopy.error.must_specify_message_number")
            break
          end
          requested_message_count = default_history_count
        elsif requested_message_count.nil? || requested_message_count <= 0
          error_key =
            if thread_channel
              "discord_bot.commands.disccopy.error.must_specify_message_number_as_integer"
            else
              "discord_bot.commands.disccopy.error.must_specify_message_number"
            end
          event.respond I18n.t(error_key)
          break
        end

        if requested_message_count > SiteSetting.discord_bot_message_copy_max_messages
          event.respond I18n.t(
                          "discord_bot.commands.disccopy.error.message_number_exceeds_limit",
                          limit: SiteSetting.discord_bot_message_copy_max_messages,
                        )
          break
        end

        past_messages = fetch_history(event.channel, event.message.id, requested_message_count)

        if past_messages.empty?
          event.respond I18n.t("discord_bot.commands.disccopy.error.no_messages_found")
          break
        end

        # if beginning of thread, strip the first message and replace it with its parent message that kicked off the thread (ugh!)
        if past_messages.any? && past_messages.last.content.blank? && thread_channel
          past_messages =
            past_messages[0..past_messages.length - 2] << event
              .bot
              .channel(event.channel.parent_id)
              .message(event.channel.id)
        end

        destination_topic = nil
        automatic_sync_topic_title = nil
        if target_category.nil?
          channel_category = Category.find_by(name: event.message.channel.name)
          destination_category =
            channel_category ||
              Category.find_by(id: SiteSetting.discord_bot_message_copy_default_category)
          event.respond I18n.t("discord_bot.commands.disccopy.no_category_specified")
        else
          target_category = target_category.gsub /_/, " "
          destination_category = Category.find_by(name: target_category)
        end
        if destination_category
          event.respond I18n.t(
                          "discord_bot.commands.disccopy.success.found_matching_discourse_category",
                          name: destination_category.name,
                        )
        else
          event.respond I18n.t(
                          "discord_bot.commands.disccopy.error.unable_to_find_discourse_category",
                        )
          break
        end
        if target_topic.nil?
          if SiteSetting.discord_bot_auto_channel_sync && channel_category == destination_category
            automatic_sync_topic_title =
              I18n.t(
                "discord_bot.discord_events.auto_message_copy.default_topic_title",
                channel_name: destination_category.name,
              )
            destination_topic =
              Topic.find_by(title: automatic_sync_topic_title, category_id: destination_category.id)
          end
        else
          target_topic = target_topic.gsub /_/, " "
          destination_topic =
            Topic.find_by(title: target_topic, category_id: destination_category.id)
          if destination_topic
            event.respond I18n.t(
                            "discord_bot.commands.disccopy.success.found_matching_discourse_topic",
                          )
          else
            event.respond I18n.t(
                            "discord_bot.commands.disccopy.error.unable_to_find_discourse_topic",
                          )
          end
        end
        total_copied_messages = 0
        current_topic_id = nil
        bot_user_id = Base64.decode64(bot.token.split(" ")[1].split(".")[0]).to_i
        prepared_posts =
          past_messages.compact.zip(::DiscordBot::Utils.prepare_posts(past_messages.compact)).to_h

        past_messages
          .reverse
          .in_groups_of(SiteSetting.discord_bot_message_copy_topic_size_limit.to_i)
          .each_with_index do |message_batch, index|
            message_batch.each_with_index do |pm, topic_index|
              next if pm.nil?
              if SiteSetting.discord_bot_message_copy_ignore_bot_messages &&
                   pm.author.id == bot_user_id
                next
              end

              posting_user, raw = prepared_posts.fetch(pm)

              if topic_index == 0 && destination_topic.nil?
                raw =
                  (
                    raw.presence ||
                      I18n.t(
                        "discord_bot.commands.disccopy.discourse_topic_contents",
                        channel: event.channel.name,
                      )
                  )
                # because of structure of Discord if we are copying thread we want the link on second message, ugh!
                if thread_types.include?(event.channel.type) && message_batch.length > 1
                  link_to_discord = message_batch[1].link
                else
                  link_to_discord = pm.link
                end

                raw =
                  raw +
                    I18n.t(
                      "discord_bot.commands.disccopy.link_to_discord",
                      link_to_discord: link_to_discord,
                    )
                new_post =
                  PostCreator.create!(
                    posting_user,
                    title:
                      automatic_sync_topic_title ||
                        I18n.t(
                          "discord_bot.commands.disccopy.discourse_topic_title",
                          channel: event.channel.name,
                        ) +
                          (
                            if past_messages.count <=
                                 SiteSetting.discord_bot_message_copy_topic_size_limit
                              ""
                            else
                              " #{index + 1}"
                            end
                          ),
                    raw: raw,
                    category: destination_category.id,
                    skip_validations: true,
                  )
                total_copied_messages += 1
                current_topic_id = new_post.topic.id
                destination_topic = new_post.topic if automatic_sync_topic_title
              elsif !destination_topic.nil? || !current_topic_id.nil?
                current_topic_id = destination_topic.id if current_topic_id.nil?
                new_post =
                  PostCreator.create!(
                    posting_user,
                    raw: raw,
                    topic_id: current_topic_id,
                    skip_validations: true,
                  )
                total_copied_messages += 1
              else
                event.respond I18n.t(
                                "discord_bot.commands.disccopy.error.unable_to_determine_topic_id",
                              )
              end
            end
          end
        event.respond I18n.t(
                        "discord_bot.commands.disccopy.success.final_outcome",
                        count: total_copied_messages,
                      )
        url = "https://#{Discourse.current_hostname}/t/slug/#{current_topic_id}"
        event.respond I18n.t("discord_bot.commands.disccopy.success.link", url: url)
      end
    rescue => e
      event.respond I18n.t("discord_bot.commands.disccopy.error.general_error", error: e)
      Rails.logger.error("Discord Bot: There was a problem: #{e}")
    end

    # '!disckick' - a command to kick members beneath a certain trust level on Discourse

    bot.command(
      :disckick,
      min_args: 0,
      max_args: 1,
      bucket: :admin_tasks,
      rate_limit_message: I18n.t("discord_bot.commands.rate_limit_breached"),
      required_roles: [SiteSetting.discord_bot_admin_role_id],
      description: I18n.t("discord_bot.commands.disckick.description"),
    ) do |event, min_trust_level|
      ::DiscordBot::Manager.with_bot_connection(event.bot) do
        min_trust_level = 3 if !min_trust_level

        event.respond "Discourse Kick:  Starting.  Minimum Trust Level = #{min_trust_level}"
        event.respond "Discourse Kick:  Starting.  Please be patient, I'm rate limited to respect Discord services."
        event.respond "Discourse Kick:  Preparing list of users who also have a registered account on Discord ..."

        event.respond "Discourse Kick:  Determining user trust levels ..."
        event.respond "Discourse Kick:  Compiling list of untrusted users ..."

        untrusted_user_ids = discord_users_below_trust_level(min_trust_level.to_i)

        bot_profile = bot.profile.on(event.server)
        can_do_the_magic_dance = bot_profile.permission?(:kick_members)

        if can_do_the_magic_dance == true
          ut_count = untrusted_user_ids.count

          if ut_count > 0
            untrusted_user_ids.each_with_index do |user_id, index|
              event.server.kick(
                user_id.to_s,
                "Kicked for not having sufficient trust level on the linked Discourse site",
              )
              event.respond "Discourse Kick:  [#{index + 1}/#{ut_count}] <@#{user_id}> has been kicked for having insufficient trust level on the linked Discourse site"
              sleep(SiteSetting.discord_bot_rate_limit_delay)
            rescue => e
              event.respond "Discourse Kick:  The user you are trying to kick has a role higher than/equal to me."
              bot.send_message(
                SiteSetting.discord_bot_admin_channel_id,
                "ERROR on server #{event.server.name} (ID: #{event.server.id}) for command `^kick`, `#{e}`",
              )
            end
          else
            event.respond "Discourse Kick:  Great news!  There were no users below the specified or default trust level!"
          end
        else
          event.respond 'Discourse Kick:  Sorry, but I do not have the "Kick Members" permission'
        end
        event.respond "Discourse Kick:  I'm done with the dirty work!"
      end
    end

    # '!discsync' - a command to pull all the groups that Discord using members are a member of and set them up on Discord inc. adding those Roles to users accordingly

    bot.command(
      :discsync,
      min_args: 0,
      max_args: 3,
      bucket: :admin_tasks,
      rate_limit_message: I18n.t("discord_bot.commands.rate_limit_breached"),
      required_roles: [SiteSetting.discord_bot_admin_role_id],
      description: "Block users whose trust level is below a certain integer on discourse",
    ) do |event, clean_house, max_group_visibility, include_automated_groups|
      ::DiscordBot::Manager.with_bot_connection(event.bot) do
        clean_house = false if !clean_house
        max_group_visibility = 0 if !max_group_visibility

        event.respond "Discourse Sync:  Starting.  Please be patient, I'm rate limited to respect Discord services."
        event.respond "Discourse Sync:  Checking if there are any eligible groups for sync ..."

        eligible_group_count, user_group_memberships =
          group_sync_data(
            max_group_visibility.to_i,
            include_automated_groups: include_automated_groups.to_s.downcase == "true",
          )

        event.respond "Discourse Sync: #{eligible_group_count} eligible group(s) were found"

        if eligible_group_count == 0
          event.respond "Discourse Sync:  No eligible groups for sync using provided or default criteria!"
        else
          event.respond "Discourse Sync:  Preparing linked Discord users and their Discourse groups ..."

          discourse_groups =
            user_group_memberships
              .map do |membership|
                {
                  discourse_group_id: membership[:discourse_group_id],
                  discourse_name: membership[:discourse_group_name],
                }
              end
              .uniq

          event.respond "Discourse Sync: #{discourse_groups.length} eligible group(s) were found with Discord users"

          if discourse_groups.length == 0
            event.respond "Discourse Sync:  No users were found in elibigle groups for sync using provided or default criteria!"
          else
            event.respond "Discourse Sync:  Retrieving list of roles from Discord server ..."

            discord_roles = event.server.roles.index_by(&:name)

            if clean_house.to_s.downcase == "true"
              event.respond "Discourse Sync:  Deleting existing mapping roles ..."

              discourse_groups_count = discourse_groups.count

              discourse_groups.each_with_index do |group, index|
                event.respond "Discourse Sync:  [#{index + 1}/#{discourse_groups_count}] Attempting to delete Role"

                role = discord_roles[group[:discourse_name]]
                next if role.nil?

                begin
                  role.delete("Discourse Sync Cleanup")
                  event.respond "Discourse Sync:  Role '#{group[:discourse_name]}' deleted as part of cleanup"
                  sleep(SiteSetting.discord_bot_rate_limit_delay)
                rescue => e
                  event.respond "Discourse Sync:  I dont appear to have rights to do this though!"
                  bot.send_message(
                    SiteSetting.discord_bot_admin_channel_id,
                    "ERROR on server #{event.server.name} (ID: #{event.server.id}) for command `^role deletion`, `#{e}`",
                  )
                end
              end
            end

            event.respond "Discourse Sync:  Creating missing Roles on Discord server ..."

            discord_roles = event.server.roles.index_by(&:name)
            discourse_groups_count = discourse_groups.count

            discourse_groups.each_with_index do |group, index|
              group_name = group[:discourse_name]
              event.respond "Discourse Sync:  [#{index + 1}/#{discourse_groups_count}] Attempting to create Role for #{group_name}"

              if discord_roles.key?(group_name)
                event.respond "Discourse Sync:  Role '#{group_name}' already exists!"
              else
                begin
                  event.server.create_role(name: group_name)
                  event.respond "Discourse Sync:  Role '#{group_name}' created!"
                rescue => e
                  event.respond "Discourse Sync:  I dont appear to have rights to create Roles!"
                  bot.send_message(
                    SiteSetting.discord_bot_admin_channel_id,
                    "ERROR on server #{event.server.name} (ID: #{event.server.id}) for command `^role create`, `#{e}`",
                  )
                end
              end

              sleep(SiteSetting.discord_bot_rate_limit_delay)
            end

            discord_roles = event.server.roles.index_by(&:name)

            event.respond "Discourse Sync:  Adding users to roles ..."

            membership_count = user_group_memberships.count
            user_group_memberships.each_with_index do |membership, index|
              group_name = membership[:discourse_group_name]
              role = discord_roles[group_name]
              event.respond "Discourse Sync:  [#{index + 1}/#{membership_count}] Adding member '#{membership[:discourse_username]}' to '#{group_name}'"
              event.server.member(membership[:discord_uid]).add_role(role&.id)
              sleep(SiteSetting.discord_bot_rate_limit_delay)
            rescue => e
              event.respond "Discourse Sync:  I dont appear to have rights to do this though!"
              bot.send_message(
                SiteSetting.discord_bot_admin_channel_id,
                "ERROR on server #{event.server.name} (ID: #{event.server.id}) for command `^add_role`, `#{e}`",
              )
            end

            event.respond "Discourse Sync:  DONE!"
          end
        end
      end
    end

    bot.message(with_text: "Ping!") do |event|
      ::DiscordBot::Manager.with_bot_connection(event.bot) { event.respond "Pong!" }
    end
  end
end
