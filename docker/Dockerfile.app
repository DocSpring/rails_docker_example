FROM demoapp/app:base-build as gems

ADD Gemfile Gemfile.lock /app/
# This COPY command is much slower than just installing a couple of new gems.
# COPY --from=demoapp/app:latest-build /app/vendor/bundle /app/vendor/bundle
RUN bundle config --global frozen 1 \
    && bundle install --without development:test -j4 \
        --path vendor/bundle \
        --binstubs vendor/bundle/bin \
        --deployment \
    && find vendor/bundle/ruby/*/extensions \
        -type f -name "mkmf.log" -o -name "gem_make.out" | xargs rm -f \
    && find vendor/bundle/ruby/*/gems -maxdepth 2 \
        \( -type d -name "spec" -o -name "test" -o -name "docs" \) -o \
        \( -name "*LICENSE*" -o -name "README*" -o -name "CHANGELOG*" \
            -o -name "*.md" -o -name "*.txt" -o -name ".gitignore" -o -name ".travis.yml" \
            -o -name ".rubocop.yml" -o -name ".yardopts" -o -name ".rspec" \
            -o -name "appveyor.yml" -o -name "COPYING" -o -name "SECURITY" \
            -o -name "HISTORY" -o -name "CODE_OF_CONDUCT" -o -name "CONTRIBUTING" \
        \) | xargs rm -rf

FROM gems as npm_rake

ADD package.json yarn.lock /app/
ADD client/package.json client/yarn.lock /app/client/
# These COPY commands are much slower than installing a couple of new packages.
# COPY --from=demoapp/app:latest-build /app/node_modules /app/node_modules
# COPY --from=demoapp/app:latest-build /app/client/node_modules /app/client/node_modules
RUN yarn install

ADD Rakefile /app/Rakefile
ADD config/initializers/assets.rb \
    config/initializers/react_on_rails.rb \
    /app/config/initializers/
ADD config/environments/production.rb  /app/config/environments/
ADD config/locales /app/config/locales
ADD config/application.rb \
    config/boot.rb \
    config/environment.rb \
    config/secrets.yml \
    /app/config/
ADD lib/tasks/assets.rake                   /app/lib/tasks/assets.rake

FROM npm_rake as webpack
ARG SECRET_KEY_BASE

# Only add files that affect the webpack build
ADD client                                  /app/client
ADD config/webpacker.yml                    /app/config/webpacker.yml
RUN rake react_on_rails:locale
RUN cd client && yarn run build:production

FROM npm_rake as assets
ARG SECRET_KEY_BASE

# Only add files that affect the assets:precompile task
ADD app/assets                              /app/app/assets
ADD lib/assets                              /app/lib/assets
ADD vendor/assets                           /app/vendor/assets

# Copy assets and cache from the latest build
COPY --from=demoapp/app:latest-build /app/tmp/cache/assets /app/tmp/cache/assets
COPY --from=demoapp/app:latest-build /app/public/assets /app/public/assets

RUN rake DATABASE_URL=postgresql:does_not_exist assets:precompile

# Reset image to the gems layer, copy everything and remove unneeded files
FROM gems

ADD . /app

# Remove unneeded files (including junk from ruby gems)
RUN rm -rf app/assets client node_modules log tmp \
    && mkdir log tmp

COPY --from=webpack /app/client/app/libs/i18n   /app/client/app/libs/i18n
COPY --from=webpack /app/public/webpack         /app/public/webpack
COPY --from=assets  /app/public/assets          /app/public/assets
COPY --from=assets /app/tmp/cache/bootsnap-compile-cache \
    /app/tmp/cache/bootsnap-compile-cache
COPY --from=assets /app/tmp/cache/bootsnap-load-path-cache \
    /app/tmp/cache/bootsnap-load-path-cache

RUN ln -fs /app/config/nginx.production.conf /etc/nginx/sites-enabled/rails-app

EXPOSE 80
CMD ["foreman", "start"]
