FROM demoapp/app:base-build as gems

ADD Gemfile /app/Gemfile
ADD Gemfile.lock /app/Gemfile.lock
# This COPY command is much slower than just installing a couple of new gems.
# COPY --from=demoapp/app:latest-build /app/vendor/bundle /app/vendor/bundle
RUN bundle config --global frozen 1 \
    && bundle install --without development:test -j4 \
        --path vendor/bundle \
        --binstubs vendor/bundle/bin \
        --deployment

FROM gems as assets

ADD package.json /app/package.json
ADD yarn.lock /app/yarn.lock
ADD client/package.json /app/client/package.json
ADD client/yarn.lock /app/client/yarn.lock
# These COPY commands are much slower than installing a couple of new packages.
# COPY --from=demoapp/app:latest-build /app/node_modules /app/node_modules
# COPY --from=demoapp/app:latest-build /app/client/node_modules /app/client/node_modules
RUN yarn install

# Only add files that affect the assets:precompile task
ADD Rakefile                                /app/Rakefile
ADD config/application.rb                   /app/config/application.rb
ADD config/boot.rb                          /app/config/boot.rb
ADD config/environment.rb                   /app/config/environment.rb
ADD config/environments/production.rb       /app/config/environments/production.rb
ADD config/secrets.yml                      /app/config/secrets.yml
ADD config/webpacker.yml                    /app/config/webpacker.yml
ADD config/initializers/assets.rb           /app/config/initializers/assets.rb
ADD config/initializers/react_on_rails.rb   /app/config/initializers/react_on_rails.rb
ADD config/locales                          /app/config/locales
ADD lib/tasks/assets.rake                   /app/lib/tasks/assets.rake
ADD app/assets                              /app/app/assets
ADD lib/assets                              /app/lib/assets
ADD vendor/assets                           /app/vendor/assets
ADD client                                  /app/client

# Copy assets and cache from the latest build
COPY --from=demoapp/app:latest-build /app/tmp/cache/assets /app/tmp/cache/assets
COPY --from=demoapp/app:latest-build /app/public/assets /app/public/assets

ARG SECRET_KEY_BASE
RUN rake DATABASE_URL=postgresql:does_not_exist assets:precompile

# Reset image to the gems layer, copy everything and remove unneeded files
FROM gems

ADD . /app
# Remove unneeded files (including junk from ruby gems)
RUN rm -rf app/assets client node_modules log tmp \
    && mkdir log tmp \
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

COPY --from=assets /app/public/assets /app/public/assets
COPY --from=assets /app/public/webpack /app/public/webpack
COPY --from=assets /app/client/app/libs/i18n /app/client/app/libs/i18n

RUN ln -fs /app/config/nginx.production.conf /etc/nginx/sites-enabled/rails-app

EXPOSE 80
CMD ["foreman", "start"]
