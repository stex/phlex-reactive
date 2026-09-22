# frozen_string_literal: true

# The gem's own request suite dogfoods the PUBLIC Phlex::Reactive::TestHelpers
# (issue #110) — the honesty check that the shipped helper actually works. The
# legacy names (token_for / post_action / post_announced) that the suite grew up
# on (issue #40) now thinly delegate to the public API, so every existing request
# spec exercises the public module verbatim. received_json is the one member that
# delegates to nothing: it reads what a DUMMY component renders, which is the
# suite's own convention and has no place in a shipped helper.
#
# post_multipart stays LOCAL to file_params_spec.rb (it predates the public
# post_reactive_multipart and asserts a slightly different shape); it too rides
# token_for below, so it goes through the public token path.
module ActionRequestHelpers
  include Phlex::Reactive::TestHelpers

  # Legacy alias: the suite mints class-form tokens as token_for(klass, payload).
  def token_for(klass, payload = {})
    reactive_token_for(klass, payload)
  end

  # Legacy alias: post_action(klass, act:, payload:, params:) -> the public
  # post_reactive_action(klass, act, params:, payload:). The wire (JSON body,
  # action_path, headers) is the public helper's, so the suite proves it.
  def post_action(klass, act:, payload: {}, params: {})
    post_reactive_action(klass, act, params:, payload:)
  end

  # The reflected params a dummy component renders into <pre data-testid="…">.
  # Several specs read that shape; the extraction lives here so the pattern has
  # one definition rather than a copy per file.
  def received_json(response, testid: "received")
    json = response.body[%r{data-testid="#{Regexp.escape(testid)}">(.*?)</pre>}m, 1]
    # A miss used to reach JSON.parse as nil and surface as a TypeError from
    # this file — unhelpful now that `testid:` can be mistyped, and just as
    # unhelpful when a component stopped rendering the block at all.
    raise "no <pre data-testid=\"#{testid}\"> in the response body" if json.nil?

    JSON.parse(CGI.unescapeHTML(json))
  end

  # A request carrying the empty-group announcement (issue #258) — a thin alias
  # on the public post_reactive_multipart, like the two above, so these specs
  # exercise the shipped helper rather than a private copy of the wire shape.
  def post_announced(klass, act, params: {}, empty_groups: [], payload: {})
    post_reactive_multipart(klass, act, params:, payload:, empty_groups:)
  end
end
