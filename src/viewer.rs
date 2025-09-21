use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
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
use crate::cache::TextCache;

pub fn run_viewer(article_id: &str) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
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

    // Create app state
    let mut app = ViewerApp {
        article: article.clone(),
        scroll: 0,
        mode: ViewerMode::Reading,
    };

    // Run app
    let res = run_app(&mut terminal, &mut app);

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(err) = res {
        eprintln!("Error: {:?}", err);
    }

    // Handle action after closing
    if app.mode == ViewerMode::OpenBrowser {
        open_in_browser(&article.link);
    } else if app.mode == ViewerMode::CreateNote {
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
}

fn run_app(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut ViewerApp) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui(f, app))?;

        if let Event::Key(key) = event::read()? {
            if key.kind == KeyEventKind::Press {
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                    KeyCode::Char('o') => {
                        app.mode = ViewerMode::OpenBrowser;
                        return Ok(());
                    }
                    KeyCode::Char('n') => {
                        app.mode = ViewerMode::CreateNote;
                        return Ok(());
                    }
                    KeyCode::Char('j') | KeyCode::Down => {
                        app.scroll = app.scroll.saturating_add(1);
                    }
                    KeyCode::Char('k') | KeyCode::Up => {
                        app.scroll = app.scroll.saturating_sub(1);
                    }
                    KeyCode::PageDown => {
                        app.scroll = app.scroll.saturating_add(10);
                    }
                    KeyCode::PageUp => {
                        app.scroll = app.scroll.saturating_sub(10);
                    }
                    KeyCode::Char('g') => {
                        app.scroll = 0;
                    }
                    KeyCode::Char('G') => {
                        app.scroll = 9999; // Will be clamped by widget
                    }
                    _ => {}
                }
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
    // Convert HTML content to plain text if needed
    let content = if let Some(ref content) = app.article.content {
        // Use html2text to convert HTML to markdown-like text
        html2text::from_read(content.as_bytes(), area.width as usize - 4)
    } else if let Some(ref desc) = app.article.description {
        html2text::from_read(desc.as_bytes(), area.width as usize - 4)
    } else {
        "No content available".to_string()
    };

    // Add metadata at the top
    let mut full_content = String::new();

    if let Some(ref author) = app.article.author {
        full_content.push_str(&format!("Author: {}\n", author));
    }
    if let Some(ref published) = app.article.published {
        full_content.push_str(&format!("Published: {}\n", published));
    }
    full_content.push_str(&format!("Link: {}\n", app.article.link));
    full_content.push_str("\n────────────────────────────────────────\n\n");
    full_content.push_str(&content);

    let paragraph = Paragraph::new(full_content)
        .block(
            Block::default()
                .borders(Borders::LEFT | Borders::RIGHT | Borders::BOTTOM)
                .border_style(Style::default().fg(Color::Gray)),
        )
        .wrap(Wrap { trim: true })
        .scroll((app.scroll, 0));

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
    let open_cmd = if cfg!(target_os = "macos") {
        "open"
    } else if cfg!(target_os = "linux") {
        "xdg-open"
    } else {
        return;
    };

    let _ = std::process::Command::new(open_cmd)
        .arg(url)
        .spawn();
}

fn create_note_from_article(article: &crate::models::FeedItem) -> Result<()> {
    let username = std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "user".to_string());

    let zet_path = format!("/Users/{}/git/{}/zet", username, username);
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

    std::fs::write(&filename, content)?;

    // Open in Neovim if we're in a Neovim terminal
    if std::env::var("NVIM").is_ok() {
        let _ = std::process::Command::new("nvim")
            .arg("--server")
            .arg(std::env::var("NVIM").unwrap())
            .arg("--remote")
            .arg(&filename)
            .spawn();
    }

    Ok(())
}