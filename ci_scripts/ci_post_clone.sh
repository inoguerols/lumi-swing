#!/bin/sh
# Xcode Cloud clona el repo pelado y aquí no hay .xcodeproj (está gitignorado:
# lo genera XcodeGen desde project.yml). Este hook corre justo tras el clone,
# antes de resolver el proyecto, y lo deja donde Xcode Cloud lo espera.
set -e
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
