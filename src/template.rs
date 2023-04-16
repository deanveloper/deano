use regex::{Captures, Regex};

const PAY_RANGE_TEMPLATE: &str = include_str!("template_pay_range.txt");

fn replace_template(template: &str, replacements: &[(&str, &str)]) -> String {
    let regex = replacements
        .iter()
        .map(|repl| repl.0.to_owned())
        .reduce(|a, b| format!("{a}|{b}"))
        .unwrap();
    let regex = Regex::new(&format!("({})", regex)).unwrap();

    regex
        .replace_all(template, |capture: &Captures| {
            let replacement = replacements
                .iter()
                .find(|replacement| replacement.0 == &capture[0])
                .unwrap_or_else(|| panic!("could not find replacement for {}", &capture[0]));

            replacement.1
        })
        .into_owned()
}

pub fn pay_range(user: &str, original_msg: &str) -> String {
    replace_template(
        PAY_RANGE_TEMPLATE,
        &[("@user", user), ("@msg", original_msg)],
    )
}
