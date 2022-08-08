use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct ConfigSchema {
	#[serde(rename = "DISCORD_TOKEN")]
	pub discord_token: String,
}
