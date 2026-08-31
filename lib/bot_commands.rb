# frozen_string_literal: true
module ::DiscordBot::BotCommands
  HISTORY_CHUNK_LIMIT = 100

  THREAD_TYPES = [
    Discordrb::Channel::TYPES[:news_thread],
    Discordrb::Channel::TYPES[:public_thread],
    Discordrb::Channel::TYPES[:private_thread],
  ].freeze

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
        thread_channel = THREAD_TYPES.include?(event.channel.type)
        requested_message_count = Integer(number_of_past_messages, exception: false)

        if number_of_past_messages.blank?
          if !thread_channel
            event.respond I18n.t("discord_bot.commands.disccopy.error.must_specify_message_number")
            break
          end
          requested_message_count = HISTORY_CHUNK_LIMIT
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

        # if beginning of thread, strip the first message and replace it with its parent message that kicked off the thread (ugh!)
        if past_messages.any? && past_messages.last.content.blank? && thread_channel
          past_messages =
            past_messages[0..past_messages.length - 2] << event
              .bot
              .channel(event.channel.parent_id)
              .message(event.channel.id)
        end

        destination_topic = nil
        if target_category.nil?
          destination_category =
            Category.find_by(name: event.message.channel.name) ||
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
        unless target_topic.nil?
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
        system_user =
          User.find_by(username: SiteSetting.discord_bot_unknown_user_proxy_account) ||
            User.find_by(id: -1)

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
                if THREAD_TYPES.include?(event.channel.type) && message_batch.length > 1
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

        discordusers = []

        event.respond "Discourse Kick:  Starting.  Minimum Trust Level = #{min_trust_level}"
        event.respond "Discourse Kick:  Starting.  Please be patient, I'm rate limited to respect Discord services."
        event.respond "Discourse Kick:  Preparing list of users who also have a registered account on Discord ..."

        builder = DB.build("select * from user_associated_accounts /*where*/")
        builder.where("provider_name = :provider_name", provider_name: "discord")
        builder.query.each do |t|
          discordusers << { discord_user_id: t.user_id, provider_uid: t.provider_uid }
        end

        event.respond "Discourse Kick:  Determining user trust levels ..."

        discordusers.each do |user|
          trustuser = User.find_by(id: user[:discord_user_id])
          user[:trust_level] = trustuser[:trust_level]
        end

        event.respond "Discourse Kick:  Compiling list of untrusted users ..."

        untrusted_users =
          discordusers.select { |user| user[:trust_level].to_i < min_trust_level.to_i }

        bot_profile = bot.profile.on(event.server)
        can_do_the_magic_dance = bot_profile.permission?(:kick_members)

        if can_do_the_magic_dance == true
          ut_count = untrusted_users.count

          if ut_count > 0
            untrusted_users.each_with_index do |user, index|
              user_id = user[:provider_uid]
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

        discord_users = []
        eligible_discourse_groups = []
        discourse_groups = []
        discord_roles = []
        ug_list = []

        event.respond "Discourse Sync:  Starting.  Please be patient, I'm rate limited to respect Discord services."
        event.respond "Discourse Sync:  Checking if there are any eligible groups for sync ..."

        eligiblegroupbuilder = DB.build("select id from groups /*where*/")
        eligiblegroupbuilder.where(
          "visibility_level <= :visibility",
          visibility: max_group_visibility.to_i,
        )
        unless include_automated_groups.to_s.downcase == "true"
          eligiblegroupbuilder.where("automatic = false")
        end

        event.respond "Discourse Sync: #{eligiblegroupbuilder.query.count} eligible group(s) were found"

        if eligiblegroupbuilder.query.count == 0
          event.respond "Discourse Sync:  No eligible groups for sync using provided or default criteria!"
        else
          eligiblegroupbuilder.query.each { |g| eligible_discourse_groups << g.id }

          event.respond "Discourse Sync:  Preparing list of users who also have a registered account on Discord ..."

          builder = DB.build("select * from user_associated_accounts /*where*/")
          builder.where("provider_name = :provider_name", provider_name: "discord")
          builder.query.each do |t|
            discord_users << { discourse_user_id: t.user_id, discord_uid: t.provider_uid }
          end

          event.respond "Discourse Sync:  Preparing list of groups that users who have a registered account on Discord belong to on Discourse ..."

          discord_users.each do |user|
            groupbuilder = DB.build("select group_id from group_users /*where*/")
            groupbuilder.where("user_id = :user_id", user_id: user[:discourse_user_id])
            groupbuilder.query.each do |g|
              if eligible_discourse_groups.include? g.group_id
                discourse_groups |= [discourse_group_id: g.group_id]
                ug_entry = {
                  discourse_user_id: user[:discourse_user_id],
                  discord_uid: user[:discord_uid],
                  discourse_group_id: g.group_id,
                }
                ug_list << ug_entry
              end
            end
            userbuilder = DB.build("select username from users /*where*/ limit 1")
            userbuilder.where("id = :user_id", user_id: user[:discourse_user_id])
            userbuilder.query.each do |un|
              ug_list.each do |ug|
                if ug[:discourse_user_id] == user[:discourse_user_id]
                  ug[:discourse_username] = un.username
                end
              end
            end
          end

          event.respond "Discourse Sync: #{discourse_groups.length} eligible group(s) were found with Discord users"

          if discourse_groups.length == 0
            event.respond "Discourse Sync:  No users were found in elibigle groups for sync using provided or default criteria!"
          else
            event.respond "Discourse Sync:  Retrieving list of roles from Discord server ..."

            event.server.roles.each { |r| discord_roles << { name: r.name, id: r.id } }

            discourse_groups.each do |g|
              builder = DB.build("select name from groups /*where*/ limit 1")
              builder.where("id = :group_id", group_id: g[:discourse_group_id])
              builder.query.each { |n| g[:discourse_name] = n.name }
            end

            if clean_house.to_s.downcase == "true"
              event.respond "Discourse Sync:  Deleting existing mapping roles ..."

              discourse_groups_count = discourse_groups.count

              discourse_groups.each_with_index do |g, index|
                event.respond "Discourse Sync:  [#{index + 1}/#{discourse_groups_count}] Attempting to delete Role"

                if !discord_roles.detect { |r| r[:name] == g[:discourse_name] }.nil?
                  role_id = discord_roles.detect { |r| r[:name] == g[:discourse_name] }[:id]
                else
                  role_id = nil
                end

                unless role_id.nil?
                  begin
                    event.server.role(role_id).delete("Discourse Sync Cleanup")
                    event.respond "Discourse Sync:  Role '#{g[:discourse_name]}' deleted as part of cleanup"
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
            end

            event.respond "Discourse Sync:  Creating missing Roles on Discord server ..."

            discord_roles = []

            event.server.roles.each { |r| discord_roles << { name: r.name, id: r.id } }

            discourse_groups_count = discourse_groups.count

            discourse_groups.each_with_index do |g, index|
              event.respond "Discourse Sync:  [#{index + 1}/#{discourse_groups_count}] Attempting to create Role for #{g[:discourse_name]}"

              if !discord_roles.any? { |hash| hash[:name] == g[:discourse_name] }
                begin
                  event.server.create_role(name: g[:discourse_name])
                  event.respond "Discourse Sync:  Role '#{g[:discourse_name]}' created!"
                rescue => e
                  event.respond "Discourse Sync:  I dont appear to have rights to create Roles!"
                  bot.send_message(
                    SiteSetting.discord_bot_admin_channel_id,
                    "ERROR on server #{event.server.name} (ID: #{event.server.id}) for command `^role create`, `#{e}`",
                  )
                end
              else
                event.respond "Discourse Sync:  Role '#{g[:discourse_name]}' already exists!"
              end

              sleep(SiteSetting.discord_bot_rate_limit_delay)
            end

            discord_roles = []

            event.server.roles.each { |r| discord_roles << { name: r.name, id: r.id } }

            event.respond "Discourse Sync:  Building user role mapping ..."

            ug_list.each do |ug|
              entrybuilder = DB.build("select name from groups /*where*/ limit 1")
              entrybuilder.where("id = :group_id", group_id: ug[:discourse_group_id])

              entrybuilder.query.each { |n| ug[:discourse_group_name] = n.name }

              discord_roles.each do |dr|
                ug[:discord_group_id] = dr[:id] if dr[:name] == ug[:discourse_group_name]
              end
            end

            event.respond "Discourse Sync:  Adding users to roles ..."

            ug_count = ug_list.count
            ug_list.each_with_index do |ug, index|
              event.respond "Discourse Sync:  [#{index + 1}/#{ug_count}] Adding member '#{ug[:discourse_username]}' to '#{ug[:discourse_group_name]}'"
              event.server.member(ug[:discord_uid]).add_role(ug[:discord_group_id])
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
