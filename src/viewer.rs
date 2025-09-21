use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph, Wrap},
    Frame, Terminal,
};
use std::io;
use std::io::Write;
use std::fs::OpenOptions;
use crate::cache::TextCache;

pub fn run_viewer(article_id: &str) -> Result<()> {
    // Log to file for debugging
    let log_file = "/tmp/navireader_debug.log";
    let _ = std::fs::write(log_file, format!("Starting viewer for article: {}\n", article_id));

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Load article
    let cache = TextCache::new()?;
    let articles = cache.get_articles(None)?;
    let article = articles
        .into_iter()
        .find(|a| a.id == article_id)
        .ok_or_else(|| anyhow::anyhow!("Article not found: {}", article_id))?;

    // Mark as read
    cache.mark_as_read(&article.id)?;

    // Prepare content for display
    let content = if let Some(ref content) = article.content {
        html2text::from_read(content.as_bytes(), 80)
    } else if let Some(ref desc) = article.description {
        html2text::from_read(desc.as_bytes(), 80)
    } else {
        "No content available".to_string()
    };

    // Build full content with metadata
    let mut full_content = String::new();
    if let Some(ref author) = article.author {
        full_content.push_str(&format!("Author: {}\n", author));
    }
    if let Some(ref published) = article.published {
        full_content.push_str(&format!("Published: {}\n", published));
    }
    full_content.push_str(&format!("Link: {}\n", article.link));
    full_content.push_str("\n────────────────────────────────────────\n\n");
    full_content.push_str(&content);

    // Split into lines for scrolling
    let content_lines: Vec<String> = full_content.lines().map(String::from).collect();

    // Create app state
    let mut app = ViewerApp {
        article: article.clone(),
        scroll: 0,
        mode: ViewerMode::Reading,
        content_lines,
    };

    // Run app
    let res = run_app(&mut terminal, &mut app);

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen
    )?;
    terminal.show_cursor()?;

    // Log the mode to file
    let mode_str = match app.mode {
        ViewerMode::Reading => "Reading",
        ViewerMode::OpenBrowser => "OpenBrowser",
        ViewerMode::CreateNote => "CreateNote",
    };

    if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
        let _ = writeln!(file, "TUI exited with mode: {}", mode_str);
    }

    if let Err(err) = res {
        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
            let _ = writeln!(file, "Error in run_app: {:?}", err);
        }
    }

    // Handle action after closing
    if app.mode == ViewerMode::OpenBrowser {
        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
            let _ = writeln!(file, "Opening browser with: {}", &article.link);
        }
        open_in_browser(&article.link);
    } else if app.mode == ViewerMode::CreateNote {
        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
            let _ = writeln!(file, "Creating note for article: {}", &article.title);
        }
        create_note_from_article(&article)?;
    }

    Ok(())
}

#[derive(PartialEq)]
enum ViewerMode {
    Reading,
    OpenBrowser,
    CreateNote,
}

struct ViewerApp {
    article: crate::models::FeedItem,
    scroll: u16,
    mode: ViewerMode,
    content_lines: Vec<String>,
}

fn run_app(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut ViewerApp) -> io::Result<()> {
    // Calculate max scroll based on content
    let content_height = app.content_lines.len() as u16;

    loop {
        terminal.draw(|f| ui(f, app))?;

        // Read events (blocking)
        if let Event::Key(key) = event::read()? {
            // Handle all key events
            match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => {
                        return Ok(());
                    }
                    KeyCode::Char('o') => {
                        app.mode = ViewerMode::OpenBrowser;
                        return Ok(());
                    }
                    KeyCode::Char('n') => {
                        app.mode = ViewerMode::CreateNote;
                        return Ok(());
                    }
                    KeyCode::Char('j') | KeyCode::Down => {
                        let viewport_height = terminal.size()?.height.saturating_sub(7); // Account for header/footer
                        let max_scroll = content_height.saturating_sub(viewport_height);
                        if app.scroll < max_scroll {
                            app.scroll = app.scroll.saturating_add(1);
                        }
                    }
                    KeyCode::Char('k') | KeyCode::Up => {
                        app.scroll = app.scroll.saturating_sub(1);
                    }
                    KeyCode::PageDown | KeyCode::Char(' ') => {
                        let viewport_height = terminal.size()?.height.saturating_sub(7);
                        let max_scroll = content_height.saturating_sub(viewport_height);
                        app.scroll = (app.scroll + viewport_height).min(max_scroll);
                    }
                    KeyCode::PageUp => {
                        let viewport_height = terminal.size()?.height.saturating_sub(7);
                        app.scroll = app.scroll.saturating_sub(viewport_height);
                    }
                    KeyCode::Char('g') | KeyCode::Home => {
                        app.scroll = 0;
                    }
                    KeyCode::Char('G') | KeyCode::End => {
                        let viewport_height = terminal.size()?.height.saturating_sub(7);
                        let max_scroll = content_height.saturating_sub(viewport_height);
                        app.scroll = max_scroll;
                    }
                    _ => {}
            }
        }
    }
}

fn ui(f: &mut Frame, app: &ViewerApp) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4),  // Header
            Constraint::Min(10),    // Content
            Constraint::Length(3),  // Footer
        ])
        .split(f.size());

    render_header(f, chunks[0], app);
    render_content(f, chunks[1], app);
    render_footer(f, chunks[2]);
}

fn render_header(f: &mut Frame, area: Rect, app: &ViewerApp) {
    let header_text = vec![
        Line::from(vec![
            Span::styled(
                app.article.title.clone(),
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
        ]),
        Line::from(vec![
            Span::raw("Feed: "),
            Span::styled(
                app.article.feed_url.clone(),
                Style::default().fg(Color::Yellow),
            ),
        ]),
    ];

    let header = Paragraph::new(header_text)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Blue))
                .title(" RSS Article ")
                .title_alignment(Alignment::Center),
        )
        .alignment(Alignment::Left);

    f.render_widget(header, area);
}

fn render_content(f: &mut Frame, area: Rect, app: &ViewerApp) {
    // Calculate visible range
    let viewport_height = area.height as usize;
    let start = app.scroll as usize;
    let end = (start + viewport_height).min(app.content_lines.len());

    // Get visible lines
    let visible_lines: Vec<String> = if start < app.content_lines.len() {
        app.content_lines[start..end].to_vec()
    } else {
        vec![]
    };

    // Join lines for display
    let content = visible_lines.join("\n");

    // Add scroll indicator
    let scroll_indicator = if app.content_lines.len() > viewport_height {
        let current = app.scroll as usize + 1;
        let total = app.content_lines.len();
        format!(" [{}/{}] ", current, total)
    } else {
        String::new()
    };

    let paragraph = Paragraph::new(content)
        .block(
            Block::default()
                .borders(Borders::LEFT | Borders::RIGHT | Borders::BOTTOM)
                .border_style(Style::default().fg(Color::Gray))
                .title(scroll_indicator)
                .title_alignment(Alignment::Right),
        )
        .wrap(Wrap { trim: false }); // Don't wrap since we pre-wrapped

    f.render_widget(paragraph, area);
}

fn render_footer(f: &mut Frame, area: Rect) {
    let footer_text = Line::from(vec![
        Span::styled(" q ", Style::default().bg(Color::DarkGray).fg(Color::White)),
        Span::raw(" Quit  "),
        Span::styled(" o ", Style::default().bg(Color::DarkGray).fg(Color::White)),
        Span::raw(" Open in Browser  "),
        Span::styled(" n ", Style::default().bg(Color::DarkGray).fg(Color::White)),
        Span::raw(" Create Note  "),
        Span::styled(" j/k ", Style::default().bg(Color::DarkGray).fg(Color::White)),
        Span::raw(" Scroll  "),
    ]);

    let footer = Paragraph::new(footer_text)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Blue)),
        )
        .alignment(Alignment::Center);

    f.render_widget(footer, area);
}

fn open_in_browser(url: &str) {
    if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
        let _ = writeln!(file, "open_in_browser called with URL: {}", url);
    }

    // When running inside Neovim terminal, we need to ensure the browser opens
    // in the parent session, not the terminal subprocess
    if std::env::var("NVIM").is_ok() {
        // Use shell command to ensure it runs in the right context
        let result = std::process::Command::new("sh")
            .arg("-c")
            .arg(format!("open '{}'", url))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();

        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
            let _ = writeln!(file, "Browser open (via shell) result: {:?}", result);
        }
    } else {
        // Normal execution outside of Neovim
        let open_cmd = if cfg!(target_os = "macos") {
            "open"
        } else if cfg!(target_os = "linux") {
            "xdg-open"
        } else {
            return;
        };

        let result = std::process::Command::new(open_cmd)
            .arg(url)
            .spawn();

        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
            let _ = writeln!(file, "Browser open result: {:?}", result);
        }
    }
}

fn create_note_from_article(article: &crate::models::FeedItem) -> Result<()> {
    let username = std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "user".to_string());

    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| format!("/Users/{}", username));

    let zet_path = format!("{}/git/{}/zet", home, username);
    let date = chrono::Local::now().format("%Y%m%d%H%M").to_string();
    let safe_title = article.title
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
        .collect::<String>()
        .to_lowercase();
    let safe_title = if safe_title.len() > 50 {
        safe_title.chars().take(50).collect()
    } else {
        safe_title
    };

    let filename = format!("{}/{}-{}.md", zet_path, date, safe_title);

    let mut content = String::new();
    content.push_str(&format!("# {}\n\n", article.title));
    content.push_str(&format!("Source: {}\n", article.link));
    content.push_str(&format!("Feed: {}\n", article.feed_url));
    if let Some(ref published) = article.published {
        content.push_str(&format!("Date: {}\n", published));
    }
    content.push_str("\n## Summary\n\n");

    if let Some(ref article_content) = article.content {
        let summary = html2text::from_read(article_content.as_bytes(), 80);
        let first_para = summary.split("\n\n").next().unwrap_or("");
        content.push_str(first_para);
    }

    content.push_str("\n\n## Notes\n\n");

    // Create directory if it doesn't exist
    std::fs::create_dir_all(&zet_path)?;

    std::fs::write(&filename, content)?;

    if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
        let _ = writeln!(file, "Note created: {}", filename);
    }

    // Open in Neovim if we're in a Neovim terminal
    if std::env::var("NVIM").is_ok() {
        let nvim_server = std::env::var("NVIM").unwrap();
        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
            let _ = writeln!(file, "Opening in Neovim server: {}", nvim_server);
        }
        let result = std::process::Command::new("nvim")
            .arg("--server")
            .arg(nvim_server)
            .arg("--remote")
            .arg(&filename)
            .spawn();

        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open("/tmp/navireader_debug.log") {
            let _ = writeln!(file, "Neovim spawn result: {:?}", result);
        }
    }

    Ok(())
}