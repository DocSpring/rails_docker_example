FROM demoapp/app:base-webpack-build as webpack

# Install and compile vendored libraries
ADD client/vendor /app/client/vendor
RUN cd client/vendor && yarn install
ADD config/webpacker.yml                    /app/config/webpacker.yml
RUN cd client/vendor && yarn run build:production

# Install other packages for main webpack build
ADD client/package.json client/yarn.lock /app/client/
RUN cd client && yarn install

# This would be much easier if the react_on_rails:locale task
# was done in JS instead of Ruby.
# We use a minimal Gemfile just for this step, so that we
# have completely independent caching for the webpack and assets stages
ADD client/Gemfile client/Gemfile.lock /app/
RUN bundle install
ADD Rakefile /app/Rakefile
ADD client/boot.rb /app/config/boot.rb
ADD config/initializers/assets.rb \
    config/initializers/react_on_rails.rb \
    /app/config/initializers/
ADD config/environments/production.rb /app/config/environments/
ADD config/locales /app/config/locales
ADD config/application.rb \
    config/environment.rb \
    config/secrets.yml \
    config/webpacker.yml \
    /app/config/
ARG SECRET_KEY_BASE
RUN mkdir -p /app/client/app/libs/i18n \
    && rake react_on_rails:locale
ADD client /app/client
RUN cd client && yarn run build:production


FROM demoapp/app:base-assets-build as gems

ADD Gemfile Gemfile.lock /app/
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

FROM gems as assets
ARG SECRET_KEY_BASE

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
    config/webpacker.yml \
    /app/config/
RUN mkdir -p /app/client/app/libs/i18n

# Only add files that affect the assets:precompile task
ADD app/assets                              /app/app/assets
ADD lib/assets                              /app/lib/assets
ADD vendor/assets                           /app/vendor/assets

# Copy assets and cache from the latest build
COPY --from=demoapp/app:latest-assets-build /app/tmp/cache/assets /app/tmp/cache/assets
COPY --from=demoapp/app:latest-assets-build /app/public/assets /app/public/assets

RUN rake DATABASE_URL=postgresql:does_not_exist assets:precompile

# Reset image to the gems layer, copy everything and remove unneeded files
FROM gems as final_stage

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
