use crate::template;
use anyhow::{Context as AnyhowContext, Error};
use serenity::client::Context;
use serenity::http::Http;
use serenity::model::application::interaction::InteractionResponseType;
use serenity::model::channel::Message;
use serenity::model::prelude::interaction::application_command::ApplicationCommandInteraction;
use serenity::prelude::Mentionable;

pub async fn pay_range(ctx: Context, command: &ApplicationCommandInteraction) -> Result<(), Error> {
    let messages = &command.data.resolved.messages;
    let msg = messages
        .values()
        .next()
        .context("no message in interaction")?;

    let author_name = display_name_of_author(&ctx.http, msg).await;
    let new_thread = command
        .channel_id
        .create_private_thread(&ctx.http, |thread| {
            thread.name(format!("{} pay range", author_name))
        })
        .await
        .context("failed while creating private thread")?;

    new_thread
        .send_message(&ctx.http, |sending_msg| {
            sending_msg.allowed_mentions(|allowed| allowed.users(&[msg.author.id]));
            sending_msg.content(template::pay_range(
                &msg.author.mention().to_string(),
                &msg.content,
            ))
        })
        .await
        .context("failed while sending message on private thread")?;

    command
        .create_interaction_response(&ctx.http, |response| {
            response.kind(InteractionResponseType::ChannelMessageWithSource);
            response.interaction_response_data(|data| {
                data.ephemeral(true);
                data.content(format!("thread created: {}", new_thread.mention()));

                data
            });

            response
        })
        .await
        .context("failed while responding to command")?;

    msg.delete(&ctx.http)
        .await
        .context("failed while deleting message")?;

    Ok(())
}

async fn display_name_of_author(http: &Http, msg: &Message) -> String {
    msg.author_nick(http)
        .await
        .unwrap_or_else(|| msg.author.name.clone())
}
