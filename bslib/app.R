#---- bslib ----

#---- load packages ----
library(shiny)
library(tidytuesdayR)
library(tidyverse)
library(sf)
library(rnaturalearth)
library(ggpubr)
library(RColorBrewer)
library(bslib)


#---- load data ----
feederwatch <- readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2023/2023-01-10/PFW_2021_public.csv')
site <- readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2023/2023-01-10/PFW_count_site_data_public_2021.csv')
species <- read.csv("2023-1-10 PFW-species-translation-table.csv")

#---- cleaning data ----
# select relevant columns
speciesObserved <- feederwatch %>%
  select(c(species_code,
           how_many,
           valid,
           reviewed,
           latitude,
           longitude,
           Month,
           Year))


# select relevant columns
speciesNames <- species %>%
  select(c(species_code, scientific_name))


# join the relevant columns using species_code as the key
speciesData <- inner_join(speciesObserved,
                          speciesNames,
                          by = "species_code")


# filter for species that were observed and the observations validated by an expert reviewer
validatedObservations <- speciesData %>%
  filter(valid == 1,
         reviewed == 1) %>%
  select(c(scientific_name, how_many)) %>%
  group_by(scientific_name) %>%
  tally(how_many) %>%
  `colnames<-`(c("Species Name", "Number of Observations"))


#---- where were species observed ----
world <- ne_countries(scale = "medium", returnclass = "sf")

# filter for reviewed and valid data
reviewedData <- speciesData %>%
  filter(reviewed == 1,
         valid == 1)

# get names of species
species_names <- unique(reviewedData$scientific_name)

# create colour palette
colourPalette <- get_palette(palette = "jco", 10)
colourPalette <- colorRampPalette(colourPalette)(length(species_names))
species_df <- tibble(species_names, colourPalette)

# function to find a species' location
find_species <- function(species) {
  filter(reviewedData, scientific_name == species)
}

# function to plot the species' location
plot_species <- function(species, location, species_df) {
  species_colour <- species_df |>
    filter(species_names == species) |>
    pull(colourPalette)
  
  ggplot(data = world) +
    geom_sf(fill = "white") +
    geom_point(data = location, aes(longitude, latitude, size = how_many), shape = 21, alpha = 0.4, fill = species_colour) +
    coord_sf(xlim = c(-150, -50), ylim = c(20, 70), expand = FALSE, clip = "on") +
    theme(panel.background = element_rect(fill = "white"),
          axis.title = element_blank(),
          axis.text = element_blank(),
          axis.ticks = element_blank(),
          legend.position = c(0.1, 0.15),
          legend.key = element_rect(fill = "white")) +
    labs(size = "Number observed")
}


#---- UI ----
thematic::thematic_shiny(fg = "#022C3C",
                         bg = NA, 
                         accent = NA,
                         font = "auto",
                         qualitative = NA)

ui <- page_navbar(
  title = "Tidy Tuesday: Project FeederWatch",
  
  theme = bs_theme(bg = "#F7F7F7",
                   fg = "#022C3C",
                   primary = "#561643",
                   secondary = "#F4D58D",
                   base_font = font_google("Manrope")),
  
  fillable = F,
  
  nav_panel(title = "Project FeederWatch",
            layout_sidebar(
              sidebar = sidebar(
                title = "Select a species",
                selectInput(inputId = "selected_species", 
                            label = "Select a species to see where they were spotted",
                            choices = species_names,
                            selectize = T,
                            multiple = F,
                            selected = "Spinus pinus"),
                actionButton(inputId = "button",
                             label = "View sightings"),
                br(),
                value_box(title = textOutput("value_box_title"),
                          value = textOutput("total_sightings"),
                          p("times in Winter 2020/21"),
                          showcase = bsicons::bs_icon("binoculars"),
                          showcase_layout = showcase_left_center(width = 0.3, max_height = 0.45))
                ),
              h2("Map"),
              p("With this dashboard, you can quickly visualise where species of bird were observed in North America by the FeederWatch community over Winter 2020/2021. Select a species of interest in the menu on the left then click the button and the map below will update."),
              textOutput("graph_title"),
              card(plotOutput("species_location"), full_screen = T),
              br(),
              h3("Plotted Data"),
              p("The table below describes the data shown in the map"),
              card(DT::dataTableOutput("species_table"))
              )
            ),

              
  nav_panel(title = "About",
            class = "p-3 border rounded",
            h3("What is Project FeederWatch?"),
               p(a(href = "https://feederwatch.org", "Project FeederWatch"),
                 "is a November-April survey of birds that visit backyards, nature centers, community areas, and other locales in North America."),
               p("Citizen scientists count birds for as long as they like on days of their choosing, then enter the bird counts online. The counts allow us to track what is happening to birds and contribute to a continental dataset of bird distribution and abundance."),
               p("Project FeederWatch is operated by the Cornell Lab of Ornithology and Birds Canada."),
               br(),
               h3("Why are these data important?"),
               p("With each season, FeederWatch increases in importance as a unique monitoring tool for more than 100 bird species that winter in North America."),
               p("What sets FeederWatch apart from other monitoring programs is the detailed picture that FeederWatch data provide about weekly changes in bird distribution and abundance across the United States and Canada. Importantly, FeederWatch data tell us where birds", 
                 tags$b("are"),
                 "as well as where they",
                 tags$b("are not."),
                 "This crucial information enables scientists to piece together the most accurate population maps."),
               p("Because FeederWatchers count the number of individuals of each species they see several times throughout the winter, FeederWatch data are extremely powerful for detecting and explaining gradual changes in the wintering ranges of many species. In short, FeederWatch data are important because they provide information about bird population biology that cannot be detected by any other available method.")
           ),
              
  nav_panel(title = "Data",
            class = "p-3 vw-99 border rounded",
            DT::dataTableOutput("full_data")
            ),
  
  nav_spacer()
              
)


#---- server ----
server <- function(input, output) {
  location_species <- eventReactive(input$button, {
    find_species(input$selected_species)
  }, ignoreNULL = F)
  
  graph_title_event <- eventReactive(input$button, {
    paste0("Sites where ", input$selected_species, " has been observed")
  }, ignoreNULL = F)
  
  output$graph_title <- renderText({
    graph_title_event()
  })
  
  species_plot <- eventReactive(input$button, {
    plot_species(input$selected_species, location_species(), species_df)
  }, ignoreNULL = F)
  
  output$species_location <- renderPlot({
    species_plot()
  })
  
  output$species_table <- DT::renderDataTable({
    location_species() |>
      select(c("how_many", "latitude", "longitude", "Month", "Year")) |>
      rename("Number spotted" = "how_many") |>
      arrange(Year, Month)
  }, options = list(pageLength = 20), rownames = F, fillContainer = TRUE)
  
  output$total_sightings <- renderText({
    location_species() |>
      select(c("how_many", "latitude", "longitude", "Month", "Year")) |>
      rename("Number spotted" = "how_many") |>
      arrange(Year, Month) |>
      tally(`Number spotted`) |>
      as.integer()
  })
  
  value_box_title_event <- eventReactive(input$button, {
    paste0(input$selected_species, " was spotted")
  }, ignoreNULL = F)
  
  output$value_box_title <- renderText({
    value_box_title_event()
  })

  output$full_data <- DT::renderDataTable({
    reviewedData
  }, options = list(pageLength = 50), rownames = F)
}


#---- create app ----
shinyApp(ui, server)