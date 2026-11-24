require 'rails_helper'

RSpec.describe AgentBotPages::FetchService do
  let(:url) { 'https://example.com/founders' }
  let(:page) { create(:agent_bot_page, url: url) }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
  end

  def stub_page(body, content_type: 'text/html; charset=utf-8')
    stub_request(:get, url).to_return(status: 200, body: body, headers: { 'Content-Type' => content_type })
  end

  def fetch
    described_class.new(page: page).perform
    page.reload
  end

  describe 'a page that loads' do
    it 'keeps the title and the readable main text' do
      stub_page(<<~HTML)
        <html>
          <head><title>Scramble</title><meta property="og:title" content="  Funding for   founders "><style>p { color: red; }</style></head>
          <body>
            <header>Site header</header><nav>Menu</nav>
            <main>
              <h1>Funding&nbsp;for brands</h1>
              <p>We fund   consumer brands.<br>No   fees.</p>
              <ul><li>Fast</li><li>Flexible</li></ul>
              <script>track();</script><form>Subscribe</form><svg><text>Logo</text></svg>
            </main>
            <aside>Related</aside>
            <footer>Footer</footer>
          </body>
        </html>
      HTML

      freeze_time do
        expect(fetch).to have_attributes(
          status: 'fetched', title: 'Funding for founders', fetched_at: Time.current, error_message: nil,
          content: "# Funding for brands\n\nWe fund consumer brands.\nNo fees.\n\n- Fast\n- Flexible"
        )
      end
    end

    it 'takes the page title and the article, or else the body' do
      stub_page('<html><head><title> Fees </title></head><body><p>Intro</p><article><p>Article text</p></article></body></html>')
      expect(fetch).to have_attributes(title: 'Fees', content: 'Article text')

      stub_page('<html><body><nav>Menu</nav><p>Body text</p><footer>Footer</footer></body></html>')
      expect(fetch).to have_attributes(title: nil, content: 'Body text')
    end

    it 'reads XHTML and a page in another charset' do
      stub_page('<html><head><meta charset="windows-1251"></head><body><p>Привет</p></body></html>'.encode('windows-1251'),
                content_type: 'application/xhtml+xml')

      expect(fetch).to have_attributes(status: 'fetched', content: 'Привет')
    end

    it 'cuts a long title and text' do
      stub_page("<html><head><title>#{'t' * 300}</title></head><body><p>#{'a' * 30_100}</p></body></html>")

      fetched_page = fetch
      expect(fetched_page.title.length).to eq(255)
      expect(fetched_page.content.length).to eq(AgentBotPage::CONTENT_LIMIT)
    end
  end

  describe 'a page that fails' do
    let(:page) do
      create(:agent_bot_page, url: url, status: :fetched, title: 'Old title', content: 'Old text.', fetched_at: Time.zone.at(1_700_000_000))
    end

    it 'marks the page failed and keeps its content' do
      stub_request(:get, url).to_return(status: [404, 'Not Found'])

      expect(fetch).to have_attributes(status: 'failed', error_message: '404 Not Found', title: 'Old title', content: 'Old text.',
                                       fetched_at: Time.zone.at(1_700_000_000))
    end

    it 'rejects a file that is not a web page' do
      stub_page('%PDF-1.7', content_type: 'application/pdf')

      expect(fetch).to have_attributes(status: 'failed', error_message: 'content-type not allowed: application/pdf', content: 'Old text.')
    end

    it 'rejects a page over the size limit' do
      stub_const("#{described_class}::MAX_BYTES", 100)
      stub_page("<html><body><p>#{'a' * 200}</p></body></html>")

      expect(fetch).to have_attributes(status: 'failed', error_message: 'exceeded 100 bytes')
    end

    it 'rejects a page without readable text' do
      stub_page('<html><body><nav>Menu</nav><script>render();</script></body></html>')

      expect(fetch).to have_attributes(status: 'failed', error_message: 'The page has no readable text', content: 'Old text.')
    end

    it 'does not request a private network address' do
      private_url = 'http://intranet.example.com/founders'
      page.update!(url: private_url)
      allow(Resolv).to receive(:getaddresses).with('intranet.example.com').and_return(['10.0.0.5'])

      expect(fetch).to have_attributes(status: 'failed', content: 'Old text.')
      expect(page.error_message).to be_present
      expect(a_request(:get, private_url)).not_to have_been_made
    end

    it 'fails on a timeout' do
      stub_request(:get, url).to_timeout

      expect(fetch).to have_attributes(status: 'failed', content: 'Old text.')
      expect(page.error_message).to be_present
    end

    it 'cuts a long error message' do
      stub_request(:get, url).to_return(status: [500, 'e' * 2_000])

      expect(fetch.error_message.length).to eq(1_000)
    end
  end
end
