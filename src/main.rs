mod commands;
mod read_config;
mod template;

use crate::commands::pay_range;
use serenity::async_trait;
use serenity::framework::StandardFramework;
use serenity::model::application::command::Command;
use serenity::model::application::interaction::Interaction;
use serenity::model::gateway::Ready;
use serenity::model::prelude::command::CommandType;
use serenity::model::Permissions;
use serenity::prelude::*;
use serenity::Client;
use std::fs::File;

struct Handler;

#[async_trait]
impl EventHandler for Handler {
    async fn ready(&self, ctx: Context, ready: Ready) {
        println!("{} is connected!", ready.user.name);
        Command::set_global_application_commands(ctx, |commands| {
            commands.create_application_command(|c| {
                c.name("require pay range");
                c.kind(CommandType::Message);
                c.dm_permission(false);
                c.default_member_permissions(
                    Permissions::MANAGE_MESSAGES
                        | Permissions::CREATE_PRIVATE_THREADS
                        | Permissions::SEND_MESSAGES_IN_THREADS,
                );

                c
            });

            commands
        })
        .await
        .expect("error lol");
    }

    async fn interaction_create(&self, ctx: Context, interaction: Interaction) {
        if let Interaction::ApplicationCommand(command) = interaction {
            if command.data.name == "require pay range" {
                if let Err(err) = pay_range(ctx, &command).await {
                    eprintln!(
                        "Error occurred during 'require pay range' interaction:\n{}",
                        err
                    )
                }
            }
        }
    }
}

#[tokio::main]
async fn main() {
    // Configure the client with your Discord bot token in the environment.
    let config: read_config::ConfigSchema =
        serde_json::from_reader(File::open("resources/config.private.json").expect("file io err"))
            .expect("error reading file");

    // Build our client.
    let mut client = Client::builder(config.discord_token, GatewayIntents::empty())
        .framework(StandardFramework::new())
        .event_handler(Handler)
        .await
        .expect("Error creating client");

    // Finally, start a single shard, and start listening to events.
    //
    // Shards will automatically attempt to reconnect, and will perform
    // exponential backoff until it reconnects.
    if let Err(why) = client.start().await {
        println!("Client error: {:?}", why);
    }
}
