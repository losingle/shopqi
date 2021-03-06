#encoding: utf-8
class Admin::OrdersController < Admin::AppController
  prepend_before_filter :authenticate_user!
  layout 'admin'

  expose(:shop) { current_user.shop }
  expose(:orders) { shop.orders }
  expose(:order)
  expose(:customer) { order.customer }
  expose(:order_json) do
    order.to_json({
      methods: [ :gateway, :status_name, :financial_status_name, :fulfillment_status_name, :shipping_rate_price, :other_orders ],
      include: {
        line_items: { methods: [:total_price, :fulfillment_created_at, :product_deleted] },
        transactions: {},
        histories: {},
        discount: { only: [:code, :amount] }
      },
      except: [ :updated_at ]
    })
  end
  expose(:status) { KeyValues::Order::Status.hash }
  expose(:financial_status) { KeyValues::Order::FinancialStatus.hash }
  expose(:fulfillment_status) { KeyValues::Order::FulfillmentStatus.hash }
  expose(:cancel_reasons) { KeyValues::Order::CancelReason.hash }
  expose(:tracking_companies) { KeyValues::Order::TrackingCompany.hash }
  expose(:latest_tracking_company) { shop.redis order.latest_tracking_company_key }
  expose(:latest_tracking_number) { shop.redis order.latest_tracking_number_key }
  expose(:page_sizes) { KeyValues::PageSize.hash }

  def index
    render action: :blank_slate and return if shop.orders.empty?
    @limit = 50
    page = params[:page] || 1
    orders = if params[:search]
      @limit = params[:search].delete(:limit) || @limit
      params[:search][:financial_status_ne] = :abandoned if params[:search][:financial_status_eq].blank?
      params[:search][:status_eq] = :open if params[:search][:status_eq].blank?
      shop.orders.metasearch(params[:search])
    else
      shop.orders.metasearch(status_eq: :open, financial_status_ne: :abandoned)
    end
    orders = orders.page(page).per(@limit)
    @pagination = {total_count: orders.total_count, page: page.to_i, limit: @limit, results: orders.as_json(
      include: {
        customer: {only: [:id, :name]},
        line_items: {only: [:name, :quantity]},
        shipping_address: {only: [:name], methods: [:info]}
      },
      methods: [ :status_name, :financial_status_name, :fulfillment_status_name, :shipping_name ],
      except: [ :updated_at ]
    )}.to_json
    respond_to do |format|
      format.html
      format.js { render json: @pagination }
    end
  end

  # 批量修改
  def set
    operation = params[:operation].to_sym
    ids = params[:orders]
    if [:open, :close].include?(operation)
      value = (operation == :close) ? :closed : :open
      Order.transaction do
        shop.orders.find(ids).each do |order|
          order.status = value
          order.save
        end
      end
    else #支付授权
    end
    render nothing: true
  end

  def update
    render text: order.save
  end

  def close
    order.status = :closed
    order.save
    redirect_to orders_path
  end

  def open
    order.status = :open
    order.save
    redirect_to order_path(order)
  end

  def cancel
    order.cancel!
    order.send_email('order_cancelled') if params[:email]
    redirect_to orders_path
  end

  def destroy
    order.destroy
    redirect_to orders_path
  end
end
