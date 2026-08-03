# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t aperto_wine .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name aperto_wine aperto_wine

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away stage that installs the npm packages the Tailwind build needs.
# app/assets/tailwind/application.css loads daisyui with @plugin, and the
# standalone tailwindcss binary resolves plugins from node_modules — so the
# packages have to exist even though nothing here ever runs Node. .dockerignore
# excludes the host's node_modules on purpose, so this installs from the lockfile.
FROM node:22-slim AS node_modules

WORKDIR /rails

COPY package.json package-lock.json ./
RUN npm ci

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

COPY --from=node_modules /rails/node_modules ./node_modules

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# app/assets/svg/icons is gitignored (see docs/ASSETS.md): the Phosphor set is
# synced per checkout rather than committed, so a clean clone does not have it
# and every icon(...) call would raise Icons::IconNotFound at request time.
# Redirecting stdin keeps the gem's interactive "remove the temp files?" prompt
# from stalling the build if the upstream clone fails.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails generate rails_icons:sync --library=phosphor --force --quiet </dev/null

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
