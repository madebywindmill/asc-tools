# asc-tools

Small, open-source tools for App Store Connect tasks, from the makers of
[AppTraction](https://apptraction.dev). Each tool is a single file you can read
before you run it.

## activate-reports

Asks Apple to start making **analytics reports** for your apps: daily reports from now on, plus your app’s past data.

Apple only lets an **Admin** key do this, and there’s no button for it on the App Store Connect website. It can only be done through Apple’s API. This tool does it for you without giving your Admin key to any app.

### Run it

Paste this into Terminal:

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/madebywindmill/asc-tools/v1/activate-reports.zsh)"
```

It will:

1. Ask you to drag in your Admin key file (`AuthKey_….p8`) and for your issuer ID. [Getting a key](#getting-a-key), below, shows where to find both.
2. List your apps so you can choose which ones to activate.
3. Show what it will change and ask before changing anything.
4. Tell you how each app went.

Running it again is safe. Apps that are already active are left alone.

### Getting a key

In App Store Connect, go to
[Users and Access › Integrations › App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
and generate a **Team Key** with the **Admin** role. Download its `.p8` file. Apple lets you download each key only once. Your issuer ID is on the same page.

### Checking status

To see each app’s report status without changing anything, add `--check`. A key with the Admin, Sales and Reports, or Finance role works for this.

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/madebywindmill/asc-tools/v1/activate-reports.zsh)" \
    activate-reports --check
```

### What happens to your key

- The tool only reads the key file in its original location. It never copies, moves, saves, or sends it.
- Apple’s built-in `openssl` uses the key to sign a token that expires after 10 minutes. Only that token is sent, and only to `api.appstoreconnect.apple.com`.
- The tool saves nothing, except your issuer ID if you say yes when it asks. That’s kept with `defaults` (`com.madebywindmill.asc-tools`), and isn’t a secret. Run the tool with `--forget-issuer` to delete it.
- It uses only programs that come with macOS (such as `curl`, `openssl`, and `plutil`).

*If you created the Admin key just for this, you can revoke it afterward.*

### Options

Everything is optional. Anything you leave out, the tool asks for.

| Option | Meaning |
|---|---|
| `--key <path>` | Your key file. Admin to activate; Admin, Sales and Reports, or Finance with `--check` |
| `--key-id <id>` | The key ID, if the file isn’t named `AuthKey_<ID>.p8` |
| `--issuer <id>` | Your issuer ID |
| `--app <id>[=<name>]` | An app ID, with an optional name. Repeat for more. Without it, you pick from a list. |
| `--new-history <id>` | Request past data again even if an older request exists |
| `--check` | Only show each app’s report status |
| `--forget-issuer` | Delete the remembered issuer ID if it was previously saved |

To pass options, add them after the command:

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/madebywindmill/asc-tools/v1/activate-reports.zsh)" \
    activate-reports --issuer <your-issuer-id> --app 1234567890=MyApp
```

Keep the word `activate-reports` before your options. zsh treats the first word as the tool’s name.

### Versioning

`v1` is a fixed version that never changes, so you always run exactly the code you (or anyone) reviewed. Newer versions get new tags.
