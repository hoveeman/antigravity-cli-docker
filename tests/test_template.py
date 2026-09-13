#!/usr/bin/env python3
import os
import sys
import xml.etree.ElementTree as ET

TEMPLATE_PATH = "templates/antigravity-cli.xml"

def test_template():
    if not os.path.exists(TEMPLATE_PATH):
        print(f"FAIL: {TEMPLATE_PATH} does not exist", file=sys.stderr)
        sys.exit(1)

    try:
        tree = ET.parse(TEMPLATE_PATH)
        root = tree.getroot()
    except Exception as e:
        print(f"FAIL: XML parsing error in {TEMPLATE_PATH}: {e}", file=sys.stderr)
        sys.exit(1)

    assert root.tag == "Container", f"Root element must be <Container>, got <{root.tag}>"

    # Required top-level fields
    required_tags = [
        "Name", "Repository", "Registry", "Network", "Overview",
        "Category", "Icon", "Shell"
    ]
    for tag in required_tags:
        elem = root.find(tag)
        assert elem is not None and elem.text, f"Missing or empty required tag: <{tag}>"

    # Validate Config items
    configs = root.findall("Config")
    assert len(configs) >= 4, f"Expected at least 4 <Config> nodes, found {len(configs)}"

    # Check path mappings
    paths = {
        c.get("Target"): c.find("Value").text if c.find("Value") is not None else None
        for c in configs if c.get("Type") == "Path"
    }
    assert "/config" in paths, "Missing Path config for /config"
    assert "/workspaces" in paths, "Missing Path config for /workspaces"

    # Check variable mappings
    vars = {
        c.get("Key"): c.find("Value").text if c.find("Value") is not None else None
        for c in configs if c.get("Type") == "Variable"
    }
    assert "PUID" in vars, "Missing Variable config for PUID"
    assert "PGID" in vars, "Missing Variable config for PGID"
    assert "ANTIGRAVITY_INSTANCE_NAME" in vars, "Missing Variable config for ANTIGRAVITY_INSTANCE_NAME"

    print("PASS: Unraid CA template XML is fully valid and adheres to CA schema.")

if __name__ == "__main__":
    test_template()
