# frozen_string_literal: true

require "spec_helper"
require "nu/agent/persona_editor"
require "tempfile"

RSpec.describe Nu::Agent::PersonaEditor do
  let(:editor) { described_class.new }

  describe "#edit_in_editor" do
    context "when editor is available" do
      it "creates a temporary file with initial content" do
        allow(editor).to receive(:system).and_return(true)
        allow(Tempfile).to receive(:new).and_call_original

        editor.edit_in_editor(initial_content: "test content", persona_name: "test")

        expect(Tempfile).to have_received(:new).with(["nu-agent-persona-test-", ".txt"])
      end

      it "opens the editor with the temporary file" do
        allow(editor).to receive(:system).and_return(true)
        allow(ENV).to receive(:[]).with("EDITOR").and_return("nano")

        temp_file = instance_double(
          Tempfile,
          path: "/tmp/test.txt", write: nil, rewind: nil, read: "edited", close: nil, unlink: nil
        )
        allow(Tempfile).to receive(:new).and_return(temp_file)

        editor.edit_in_editor(initial_content: "test", persona_name: "test")

        expect(editor).to have_received(:system).with("nano /tmp/test.txt")
      end

      it "returns the edited content" do
        allow(editor).to receive(:system).and_return(true)
        temp_file = instance_double(
          Tempfile,
          path: "/tmp/test.txt", write: nil, rewind: nil, read: "edited content", close: nil, unlink: nil
        )
        allow(Tempfile).to receive(:new).and_return(temp_file)

        result = editor.edit_in_editor(initial_content: "original", persona_name: "test")

        expect(result).to eq("edited content")
      end

      it "cleans up the temporary file" do
        allow(editor).to receive(:system).and_return(true)
        temp_file = instance_double(
          Tempfile,
          path: "/tmp/test.txt", write: nil, rewind: nil, read: "content", close: nil, unlink: nil
        )
        allow(Tempfile).to receive(:new).and_return(temp_file)

        editor.edit_in_editor(initial_content: "test", persona_name: "test")

        expect(temp_file).to have_received(:close)
        expect(temp_file).to have_received(:unlink)
      end

      it "uses vi as default editor when EDITOR is not set" do
        allow(editor).to receive(:system).and_return(true)
        allow(ENV).to receive(:[]).with("EDITOR").and_return(nil)

        temp_file = instance_double(
          Tempfile,
          path: "/tmp/test.txt", write: nil, rewind: nil, read: "content", close: nil, unlink: nil
        )
        allow(Tempfile).to receive(:new).and_return(temp_file)

        editor.edit_in_editor(initial_content: "test", persona_name: "test")

        expect(editor).to have_received(:system).with("vi /tmp/test.txt")
      end
    end

    context "when content is empty after editing" do
      it "returns nil" do
        allow(editor).to receive(:system).and_return(true)
        temp_file = instance_double(
          Tempfile,
          path: "/tmp/test.txt", write: nil, rewind: nil, read: "", close: nil, unlink: nil
        )
        allow(Tempfile).to receive(:new).and_return(temp_file)

        result = editor.edit_in_editor(initial_content: "test", persona_name: "test")

        expect(result).to be_nil
      end

      it "returns nil when content is only whitespace" do
        allow(editor).to receive(:system).and_return(true)
        temp_file = instance_double(
          Tempfile,
          path: "/tmp/test.txt", write: nil, rewind: nil, read: "   \n\n  ", close: nil, unlink: nil
        )
        allow(Tempfile).to receive(:new).and_return(temp_file)

        result = editor.edit_in_editor(initial_content: "test", persona_name: "test")

        expect(result).to be_nil
      end
    end

    context "when editor fails" do
      it "raises an error if system returns false" do
        allow(editor).to receive(:system).and_return(false)
        temp_file = instance_double(Tempfile, path: "/tmp/test.txt", write: nil, rewind: nil, close: nil, unlink: nil)
        allow(Tempfile).to receive(:new).and_return(temp_file)

        expect do
          editor.edit_in_editor(initial_content: "test", persona_name: "test")
        end.to raise_error(Nu::Agent::PersonaEditor::EditorError)
      end

      it "raises an error if system returns nil" do
        allow(editor).to receive(:system).and_return(nil)
        temp_file = instance_double(Tempfile, path: "/tmp/test.txt", write: nil, rewind: nil, close: nil, unlink: nil)
        allow(Tempfile).to receive(:new).and_return(temp_file)

        expect do
          editor.edit_in_editor(initial_content: "test", persona_name: "test")
        end.to raise_error(Nu::Agent::PersonaEditor::EditorError)
      end
    end
  end
end
